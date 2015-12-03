# -*- encoding: utf-8 -*-
# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)

require_relative '../dtas'
require_relative 'process'
require 'socket'

# For the DTAS Music Library, based on what MPD uses.
class DTAS::Mlib
  attr_accessor :follow_outside_symlinks
  attr_accessor :follow_inside_symlinks
  attr_accessor :tags

  DM_DIR = -1
  DM_IGN = -2
  include DTAS::Process

  Job = Struct.new(:wd, :ctime, :parent_id, :path)

  # same capitalization as in mpd
  TAGS = Hash[*(
    %w(Artist ArtistSort
       Album AlbumSort
       AlbumArtist AlbumArtistSort
       Title Track Name
       Genre Date Composer Performer Comment Disc
       MUSICBRAINZ_ARTISTID MUSICBRAINZ_ALBUMID
       MUSICBRAINZ_ALBUMARTISTID
       MUSICBRAINZ_TRACKID
       MUSICBRAINZ_RELEASETRACKID).map! { |x| [ x.downcase, x ] }.flatten!)]

  def initialize(db)
    if String === db
      db = "sqlite://#{db}" unless db.include?('://')
      require 'sequel/no_core_ext'
      db = Sequel.connect(db, single_threaded: true)
    end
    if db.class.to_s.downcase.include?('sqlite')
      db.transaction_mode = :immediate
      db.synchronous = :off
    end
    @db = db
    @pwd = nil
    @follow_outside_symlinks = true
    @follow_inside_symlinks = true
    @root_node = nil
    @tags = TAGS.dup
    @tag_map = nil
    @suffixes = nil
    @work = nil
  end

  def init_suffixes
    `sox --help 2>/dev/null` =~ /\nAUDIO FILE FORMATS:\s*([^\n]+)/s
    re = $1.split(/\s+/).map { |x| Regexp.quote(x) }.join('|')
    @suffixes = Regexp.new("\\.(?:#{re})\\z", Regexp::IGNORECASE)
  end

  def worker(todo)
    @work.close
    @db.tables # reconnect before chdir
    @pwd = Dir.pwd.b
    begin
      buf = todo.recv(16384) # 4x bigger than PATH_MAX ought to be enough
      exit if buf.empty?
      job = Marshal.load(buf)
      buf.clear
      worker_work(job)
    rescue => e
      warn "#{e.message} (#{e.class}) #{e.backtrace.join("\n")}\n"
    end while true
  end

  def ignore(job)
    @db.transaction do
      node_ensure(job.parent_id, job.path, DM_IGN, job.ctime)
    end
  end

  def worker_work(job)
    tlen = nil
    wd = job.wd
    if wd != @pwd
      Dir.chdir(wd)
      @pwd = wd
    end
    tmp = {}
    path = job.path
    tlen = qx(%W(soxi -D #{path}), no_raise: true)
    return ignore(job) unless String === tlen
    tlen = tlen.to_f
    return ignore(job) if tlen < 0
    tlen = tlen.round
    buf = qx(%W(soxi -a #{path}), no_raise: true)
    return ignore(job) unless String === buf

    # no, we don't support comments with newlines in them
    buf = buf.split("\n".freeze)
    while line = buf.shift
      tag, value = line.split('='.freeze, 2)
      tag && value or next
      tag.downcase!
      tag_id = @tag_map[tag] or next
      value.strip!

      # FIXME: this fallback needs testing
      [ Encoding::UTF_8, Encoding::ISO_8859_1 ].each do |enc|
        value.force_encoding(enc)
        if value.valid_encoding?
          value.encode!(Encoding::UTF_8) if enc != Encoding::UTF_8
          tmp[tag_id] = value
          break
        end
      end
    end
    @db.transaction do
      node_id = node_ensure(job.parent_id, path, tlen, job.ctime)[:id]
      vals = @db[:vals]
      comments = @db[:comments]
      q = { node_id: node_id }
      comments.where(q).delete
      tmp.each do |tid, val|
        v = vals[val: val]
        q[:val_id] = v ? v[:id] : vals.insert(val: val)
        q[:tag_id] = tid
        comments.insert(q)
      end
    end
  end

  def update(path, jobs: 8)
    # n.b. "jobs" is for CPU concurrency.  Audio media is typically stored
    # on high-latency media or slow network file systems; so we use a high
    # number of jobs by default to compensate for the seek-heavy workload
    # this generates
    init_suffixes
    st = File.stat(path) # we always follow the first dir even if it's a symlink
    st.directory? or
      raise ArgumentError, "path: #{path.inspect} is not a directory"
    @work and raise 'update already running'
    todo, @work = UNIXSocket.pair(:SOCK_SEQPACKET)
    @db.disconnect
    jobs.times { |i| fork { worker(todo) } }
    todo.close
    scan_dir(path, st)
    @work.close
    Process.waitall
  ensure
    @work = nil
  end

  def migrate
    require 'sequel'
    Sequel.extension(:migration, :core_extensions) # ugh...
    @db.transaction do
      Sequel::Migrator.apply(@db, "#{File.dirname(__FILE__)}/mlib/migrations")
      root_node # ensure this exists
      load_tags
    end
  end

  def load_tags
    tag_map = {}
    tags = @db[:tags]
    @tags.each do |lc, mc|
      unless q = tags[tag: mc]
        q = { tag: mc }
        q[:id] = tags.insert(q)
      end
      tag_map[lc] = q[:id]
    end

    # Xiph tags use "tracknumber" and "discnumber"
    %w(track disc).each do |x|
      tag_id = tag_map[x] and tag_map["#{x}number"] = tag_id
    end
    @tag_map = tag_map
  end

  def scan_any(path, parent_id)
    st = File.lstat(path) rescue return
    if st.directory?
      scan_dir(path, st, parent_id)
    elsif st.file?
      scan_file(path, st, parent_id)
    # elsif st.symlink? TODO
      # scan_link(path, st, parent_id)
    end
  end

  def scan_file(path, st, parent_id)
    return if @suffixes !~ path || st.size == 0

    # no-op if no change
    if node = @db[:nodes][name: path, parent_id: parent_id]
      return if st.ctime.to_i == node[:ctime] || node[:tlen] == DM_IGN
    end

    job = Job.new(@pwd, st.ctime.to_i, parent_id, path)
    send_harder(@work, Marshal.dump(job))
  end

  def root_node
    q = @root_node and return q
    # root node always has parent_id: 1
    q = {
      parent_id: 1, # self
      name: '',
    }
    node = @db[:nodes][q] and return (@root_node = node)
    begin
      q[:tlen] = DM_DIR
      q[:id] = @db[:nodes].insert(q)
      q
    rescue Sequel::DatabaseError
      # we may conflict on insert if we didn't use a transaction
      raise if @db.in_transaction?
      @root_node = @db[:paths][q] or raise
    end
  end

  def dir_vivify(parts, ctime)
    @db.transaction do
      dir = root_node
      last = parts.pop
      parts.each do |name|
        dir = node_ensure(dir[:id], name, DM_DIR)
      end
      node_ensure(dir[:id], last, DM_DIR, ctime)
    end
  end

  def node_update_maybe(node, tlen, ctime)
    q = {}
    q[:ctime] = ctime if ctime && ctime != node[:ctime]
    q[:tlen] = tlen if tlen != node[:tlen]
    return if q.empty?
    node_id = node.delete(:id)
    @db[:nodes].where(id: node_id).update(node.merge(q))
    node[:id] = node_id
  end

  def node_lookup(parent_id, name)
    @db[:nodes][name: name, parent_id: parent_id]
  end

  def node_ensure(parent_id, name, tlen, ctime = nil)
    q = { name: name, parent_id: parent_id }
    if node = @db[:nodes][q]
      node_update_maybe(node, tlen, ctime)
    else
      # brand new node
      node = q.dup
      node[:tlen] = tlen
      node[:ctime] = ctime
      node[:id] = @db[:nodes].insert(node)
    end
    node
  end

  def cd(path)
    prev_wd = @pwd
    Dir.chdir(path)
    cur = @pwd = Dir.pwd.b
    yield
  ensure
    Dir.chdir(prev_wd) if cur && prev_wd
    @pwd = prev_wd
  end

  def scan_dir(path, st, parent_id = nil)
    cd(path) do
      # TODO: use parent_id if given
      dir = dir_vivify(@pwd.split(%r{/+}n), st.ctime.to_i)
      dir_id = dir[:id]

      @db[:nodes].where(parent_id: dir_id).each do |node|
        File.exist?(node[:name]) or remove_entry(node)
      end

      Dir.foreach('.', encoding: Encoding::BINARY) do |x|
        case x
        when '.', '..', %r{\n}n
          # files with newlines in them are rare and last I checked (in 2008),
          # mpd could not support them, either.  So lets not bother for now.
          next
        else
          scan_any(x, dir_id)
        end
      end
    end
  end

  def send_harder(sock, msg)
    sock.sendmsg(msg)
  rescue Errno::EMSGSIZE
    sock.setsockopt(:SOL_SOCKET, :SO_SNDBUF, msg.bytesize + 1024)
    # if it still fails, oh well...
    begin
      sock.sendmsg(msg)
    rescue => e
      warn "#{msg.bytesize} too big, dropped #{e.class}"
    end
  end

  def find_dump_part(cur, base)
    parts = @pwd.split(%r{/+}n)
    parts.shift # no first part
    parts << base if base
    parts.each do |name|
      if cur = node_lookup(cur[:id], name)
        case cur[:tlen]
        when DM_DIR then next # keep going
        when DM_IGN then return [ :ignored, cur ]
        else # regular audio
          return cur if name.object_id == parts[-1].object_id
          return [ :notdir, cur ]
        end
      else
        return [ :missing, name ]
      end
    end
    cur
  end

  # returns an array on error
  def dump(path)
    dir = path
    base = nil
    retried = false
    begin
      found = cd(dir) { find_dump_part(root_node, base) }
    rescue Errno::ENOTDIR
      raise if retried || found
      dir, base = File.split(path)
      retried = true
      retry
    end
    return found if Array === found # error

    # success
    load_tags
    @tag_rmap = @tag_map.invert
    if found[:tlen] == DM_DIR
      emit_recurse(found)
    else
      parent = @db[:nodes][id: found[:parent_id]]
      parent or abort "missing parent for #{found.inspect}"
      parent[:dirname] ||= path_of(parent)
      emit_1(found, parent)
    end
  end

  def count_distinct(tag)
    s = 'SELECT COUNT(DISTINCT(val_id)) FROM comments WHERE tag_id = ?'
    @db.fetch(s, @tag_map[tag]).single_value
  end

  def count_songs
    @db.fetch('SELECT COUNT(*) FROM nodes WHERE tlen >= 0').single_value
  end

  def db_playtime
    @db.fetch('SELECT SUM(tlen) FROM nodes WHERE tlen >= 0').single_value
  end

  def stats
    %w(artist album).each do |k|
      puts "#{k}s: #{count_distinct(k)}"
    end
    puts "songs: #{count_songs}"
    puts "db_playtime: #{db_playtime}"
  end

  def path_of(node)
    return '/' if node[:name] == ''
    parts = [ node[:name], '' ]
    begin
      node = @db[:nodes][id: node[:parent_id]]
      break if node[:id] == node[:parent_id]
      parts.unshift node[:name]
    end while true
    parts.unshift('')
    parts.join('/')
  end

  def emit_recurse(node)
    node[:dirname] ||= path_of(node)
    @db[:nodes].where(parent_id: node[:id]).order(:name).each do |nd|
      next if nd[:id] == node[:id] # root_node
      case nd[:tlen]
      when DM_DIR then emit_recurse(nd)
      when DM_IGN then next
      else
        emit_1(nd, node)
      end
    end
  end

  def emit_1(node, parent)
    comments = Hash.new { |h,k| h[k] = [] }
    @db['SELECT c.tag_id, v.val FROM comments c ' \
        'LEFT JOIN vals v ON v.id = c.val_id ' \
        "WHERE c.node_id = #{node[:id]} ORDER BY c.tag_id"].map do |c|
      comments[@tag_rmap[c[:tag_id]]] << c[:val]
    end
    puts "Path: #{parent[:dirname]}#{node[:name]}"
    puts "Length: #{node[:tlen]}"
    return if comments.empty?
    puts 'Comments:'
    comments.each do |k,v|
      if v.size == 1
        puts "\t#{k}: #{v[0]}"
      else
        v << ''
        puts "\t#{k}:\n\t\t#{v.join("\t\t\n")}"
      end
    end
    puts
  end

  def remove_entry(node)
    root_id = root_node[:id]
    node_id = node[:id]
    q = { parent_id: node_id }
    nodes = @db[:nodes]
    nodes.where(q).each do |nd|
      next if nd[:id] == root_id
      case nd[:tlen]
      when DM_DIR, DM_IGN
        remove_entry(nd)
      end
    end
    nodes.where(q).delete
    @db[:comments].where(node_id: node_id).delete
    nodes.where(id: node_id).delete
  end
end

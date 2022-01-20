# -*- encoding: utf-8 -*-
# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
#
require_relative '../dtas'
require_relative 'process'
require_relative 'source/sox'
require_relative 'source/av'
require_relative 'source/ff'
require_relative 'source/splitfx'
require 'socket'
require 'tempfile'

# For the DTAS Music Library, based on what MPD uses.
class DTAS::Mlib # :nodoc:
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
      require 'sequel'
      opts = { single_threaded: true }
      db = "sqlite://#{db}" unless db.include?('://')
      opts[:transaction_mode] = :immediate
      opts[:synchronous] = :off
      opts[:case_sensitive_like] = false # only for 'search'
      db = Sequel.connect(db, opts)
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
    @sources = [ # order matters
      (sox = DTAS::Source::Sox.new),
      DTAS::Source::Av.new,
      DTAS::Source::Ff.new,
      DTAS::Source::SplitFX.new(sox),
    ]
  end

  def synchronize
    @lock.flock(File::LOCK_EX)
    @db.transaction { yield }
  ensure
    @lock.flock(File::LOCK_UN)
  end

  def init_suffixes
    `sox --help 2>/dev/null` =~ /\nAUDIO FILE FORMATS:\s*([^\n]+)/
    re = $1.split(/\s+/).map! { |x| Regexp.quote(x) }.join('|')
    @suffixes = Regexp.new("\\.(?:#{re}|yml)\\z", Regexp::IGNORECASE)
  end

  def worker(todo, lock)
    @lock = lock
    @work.close
    synchronize { @db.tables } # reconnect before chdir
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
    synchronize do
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
    path = job.path
    found = nil
    @sources.each do |src|
      found = src.try(path) and break
    end
    return ignore(job) unless found
    tlen = found.duration
    return ignore(job) if tlen.nil? || tlen < 0
    tlen = tlen.round
    tmp = {}
    if comments = found.comments
      comments.each do |tag, value|
        tag_id = @tag_map[tag] or next
        tmp[tag_id] = value if value.valid_encoding?
      end
    end
    synchronize do
      node_id = node_ensure(job.parent_id, path, tlen, job.ctime)[:id]
      vals = @db[:vals]
      comments = @db[:comments]
      q = { node_id: node_id }
      comments.where(q).delete
      tmp.each do |tid, val|
        v = vals[val: val]
        begin
          q[:val_id] = v ? v[:id] : vals.insert(val: val)
          q[:tag_id] = tid
          comments.insert(q)
        rescue => e
          warn "E: #{e.message} (#{e.class}) q=#{q.inspect} val=#{val.inspect}"
        end
      end
    end
  end

  def update(path, opts = nil)
    # n.b. "jobs" is for CPU concurrency.  Audio media is typically stored
    # on high-latency media or slow network file systems; so we use a high
    # number of jobs by default to compensate for the seek-heavy workload
    # this generates
    opts ||= {}
    jobs = opts[:jobs] || 8
    @force = opts[:force] || false

    init_suffixes
    st = File.stat(path) # we always follow the first dir even if it's a symlink
    st.directory? or
      raise ArgumentError, "path: #{path.inspect} is not a directory"
    @work and raise 'update already running'
    todo, @work = UNIXSocket.pair(:SOCK_SEQPACKET)
    @db.disconnect

    # like a Mutex between processes
    @lock = Tempfile.new('dtas.mlib.lock')
    jobs.times do |i|
      lock = File.open(@lock.path, 'w')
      fork { worker(todo, lock) }
      lock.close
    end
    @lock.unlink
    todo.close
    scan_dir(path, st)
    @work.close
    Process.waitall
    @lock.close
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
    return @tag_map if @tag_map
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
    @tag_rmap = tag_map.invert.freeze
    tag_map.merge!(Hash[*(tag_map.map { |k,v| [-(k.upcase), v] }.flatten!)])
    @tag_map = tag_map.freeze
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

  def maybe_blob(path)
    path.valid_encoding? ? path : Sequel.blob(path)
  end

  def scan_file(path, st, parent_id)
    return if @suffixes !~ path || st.size == 0

    # no-op if no change
    unless @force
      if node = @db[:nodes][name: maybe_blob(path), parent_id: parent_id]
        return if st.ctime.to_i == node[:ctime] || node[:tlen] == DM_IGN
      end
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
    node = @db[:nodes][q]
    if node
      node[:dirname] = ''
      @root_node = node
      return node
    end
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
    synchronize do
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
  rescue => e
    warn "E: #{e.message} (#{e.class}) node=#{node.inspect}"
  end

  def node_lookup(parent_id, name)
    @db[:nodes][name: maybe_blob(name), parent_id: parent_id]
  end

  def node_ensure(parent_id, name, tlen, ctime = nil)
    q = { name: maybe_blob(name), parent_id: parent_id }
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
  rescue => e
    warn "E: #{e.message} (#{e.class}) q=#{q.inspect}"
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

      synchronize do
        @db[:nodes].where(parent_id: dir_id).each do |node|
          File.exist?(node[:name]) or remove_entry(node)
        end
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
  def dump(path, cache, cb)
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
    if found[:tlen] == DM_DIR
      emit_recurse(found, cache, cb)
    else
      parent = @db[:nodes][id: found[:parent_id]]
      parent or abort "missing parent for #{found.inspect}"
      parent[:dirname] ||= path_of(parent, cache)
      emit_1(found, parent, cache, cb)
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
    rv = { songs: count_songs, db_playtime: db_playtime }
    %w(artist album).each { |k| rv[:"#{k}s"] = count_distinct(k) }
    rv
  end

  def path_of(node, cache)
    base = node[:name]
    return '/' if base == '' # root_node
    parent_id = node[:parent_id]
    base += '/' unless node[:tlen] >= 0
    ppath = cache[parent_id] and return -"#{ppath}/#{base}"
    parts = []
    begin
      node = @db[:nodes][id: node[:parent_id]]
      break if node[:id] == node[:parent_id]
      parts.unshift node[:name]
    end while true
    parts.unshift('')
    cache[parent_id] = -(parts.join('/'))
    parts << base
    -(parts.join('/'))
  end

  def emit_recurse(node, cache, cb)
    node[:dirname] ||= path_of(node, cache)
    @db[:nodes].where(parent_id: node[:id]).order(:name).each do |nd|
      next if nd[:id] == node[:id] # root_node
      case nd[:tlen]
      when DM_DIR then emit_recurse(nd, cache, cb)
      when DM_IGN then next
      else
        emit_1(nd, node, cb)
      end
    end
  end

  def emit_1(node, parent, cb)
    comments = Hash.new { |h,k| h[k] = [] }
    @db['SELECT c.tag_id, v.val FROM comments c ' \
        'LEFT JOIN vals v ON v.id = c.val_id ' \
        "WHERE c.node_id = #{node[:id]} ORDER BY c.tag_id"].each do |c|
      comments[@tag_rmap[c[:tag_id]]] << c[:val]
    end
    cb.call(parent, node, comments)
  end

  def remove_entry(node)
    root_id = root_node[:id]
    node_id = node[:id]
    q = { parent_id: node_id }
    nodes = @db[:nodes]
    comments = @db[:comments]

    # remove children, step 1
    nodes.where(q).each do |nd|
      nd_id = nd[:id]
      next if nd_id == root_id
      case nd[:tlen]
      when DM_DIR, DM_IGN
        remove_entry(nd)
      else
        comments.where(node_id: nd_id).delete
      end
    end

    # remove children, step 2
    nodes.where(q).delete

    # finally remove ourselves
    comments.where(node_id: node_id).delete
    nodes.where(id: node_id).delete
  end

  def offset_limit(q, offset, limit)
    offset = offset.to_s
    limit = limit.to_s
    if limit =~ %r{\A\d+\z}
      q << "LIMIT #{limit}"
      q << "OFFSET #{offset}" if offset =~ %r{\A\d+\z} && offset != '0'
    end
    q
  end

  # based on the MPD command of the same name, unstable API
  def find(type, what, offset = 0, limit = nil)
    load_tags
    type = type.downcase
    q = []
    case type
    when 'any'
      # TODO: add path name matches
      q << 'SELECT DISTINCT(n.id),n.* FROM nodes n ' \
           'LEFT JOIN comments c ON c.node_id = n.id ' \
           'LEFT JOIN vals v ON v.id = c.val_id ' \
           'WHERE v.val = ?'
    when *(@tags.keys)
      tag_id = @tag_map[type]
      q << 'SELECT DISTINCT(n.id),n.* FROM nodes n ' \
           'LEFT JOIN comments c ON c.node_id = n.id ' \
           'LEFT JOIN vals v ON v.id = c.val_id ' \
           'LEFT JOIN tags t ON t.id = c.tag_id ' \
           "WHERE v.val = ? AND t.id = #{tag_id}"
    else
      raise ArgumentError, "invalid type=#{type.inspect}"
    end
    q << 'ORDER by n.parent_id,n.name'
    offset_limit(q, offset, limit)
    @db[q.join(' '), what].each { |node| yield node }
  end

  # based on the MPD command of the same name
  def search(type, what, offset = 0, limit = nil)
    load_tags
    type = type.downcase
    q = []
    what = @db.literal(%Q(%#{what}%))
    case type
    when 'any'
      # TODO: add path name matches
      q << 'SELECT DISTINCT(n.id),n.* FROM nodes n ' \
           'LEFT JOIN comments c ON c.node_id = n.id ' \
           'LEFT JOIN vals v ON v.id = c.val_id ' \
           "WHERE v.val LIKE #{what}"
    when *(@tags.keys)
      tag_id = @tag_map[type]
      q << 'SELECT DISTINCT(n.id),n.* FROM nodes n ' \
           'LEFT JOIN comments c ON c.node_id = n.id ' \
           'LEFT JOIN vals v ON v.id = c.val_id ' \
           'LEFT JOIN tags t ON t.id = c.tag_id ' \
           "WHERE t.id = #{tag_id} AND v.val LIKE #{what}"
    else
      raise ArgumentError, "invalid type=#{type.inspect}"
    end
    q << 'ORDER by n.parent_id,n.name'
    offset_limit(q, offset, limit)
    @db[q.join(' ')].each { |node| yield node }
  end
end

# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'yaml'
require 'shellwords'
require_relative '../dtas'
require_relative 'xs'
require_relative 'source'
require_relative 'source/sox'
require_relative 'source/av'
require_relative 'source/ff'
require_relative 'source/cmd'
require_relative 'sink'
require_relative 'unix_server'
require_relative 'buffer'
require_relative 'sigevent'
require_relative 'rg_state'
require_relative 'state_file'

class DTAS::Player # :nodoc:
  require_relative 'player/client_handler'
  include DTAS::XS
  include DTAS::Player::ClientHandler
  attr_accessor :state_file
  attr_accessor :socket
  attr_reader :sinks

  def initialize
    @state_file = nil
    @socket = nil
    @srv = nil
    @queue = [] # files for sources, or commands
    @paused = false
    @format = DTAS::Format.new

    @sinks = {} # { user-defined name => sink }
    @targets = [] # order matters
    @rg = DTAS::RGState.new

    # sits in between shared effects (if any) and sinks
    @sink_buf = DTAS::Buffer.new
    @current = nil
    @watchers = {}
    @source_map = {
      "sox" => DTAS::Source::Sox.new,
      "av" => DTAS::Source::Av.new,
      "ff" => DTAS::Source::Ff.new,
    }
    source_map_reload
  end

  def source_map_reload
    @sources = @source_map.values.sort_by { |src| src.tryorder }
  end

  def echo(msg)
    msg = xs(Array(msg))
    @watchers.delete_if do |io, _|
      if io.closed?
        true
      else
        case io.emit(msg)
        when :wait_readable, :wait_writable
          false
        else
          true
        end
      end
    end
    $stdout.write(msg << "\n")
  end

  # used for state file
  def to_hsh
    rv = {}
    rv["socket"] = @socket
    rv["paused"] = @paused if @paused
    src_map = rv["source"] = {}
    @source_map.each do |name, src|
      src_hsh = src.to_state_hash
      src_map[name] = src_hsh unless src_hsh.empty?
    end

    # Arrays
    rv["queue"] = @queue

    %w(rg sink_buf format).each do |k|
      rv[k] = instance_variable_get("@#{k}").to_hsh
    end

    # no empty hashes or arrays
    rv.delete_if do |k,v|
      case v
      when Hash, Array
        v.empty?
      else
        false
      end
    end

    unless @sinks.empty?
      sinks = rv["sinks"] = []
      # sort sinks by name for human viewability
      @sinks.keys.sort.each do |name|
        sinks << @sinks[name].to_hsh
      end
    end

    rv
  end

  def self.load(hash)
    rv = new
    rv.instance_eval do
      @rg = DTAS::RGState.load(hash["rg"])
      if v = hash["sink_buf"]
        v = v["buffer_size"]
        @sink_buf.buffer_size = v
      end
      %w(socket queue paused).each do |k|
        v = hash[k] or next
        instance_variable_set("@#{k}", v)
      end
      if v = hash["source"]
        # compatibility with 0.0.0, which was sox-only
        # we'll drop this after 1.0.0, or when we support a source decoder
        # named "command" or "env" :P
        sox_cmd, sox_env = v["command"], v["env"]
        if sox_cmd || sox_env
          sox = @source_map["sox"]
          sox.command = sox_cmd if sox_cmd
          sox.env = sox_env if sox_env
        end

        # new style: name = "av" or "sox" or whatever else we may support
        @source_map.each do |name, src|
          src_hsh = v[name] or next
          src.load!(src_hsh)
        end
        source_map_reload
      end

      if v = hash["format"]
        @format = DTAS::Format.load(v)
      end

      if sinks = hash["sinks"]
        sinks.each do |sink_hsh|
          sink = DTAS::Sink.load(sink_hsh)
          @sinks[sink.name] = sink
        end
      end
    end
    rv
  end

  def enq_handler(io, msg)
    # check @queue[0] in case we have no sinks
    if @current || @queue[0] || @paused
      @queue << msg
    else
      next_source(msg)
    end
    io.emit("OK")
  end

  def do_enq_head(io, msg)
    # check @queue[0] in case we have no sinks
    if @current || @queue[0] || @paused
      @queue.unshift(msg)
    else
      next_source(msg)
    end
    io.emit("OK")
  end

  # yielded from readable_iter
  def client_iter(io, msg)
    msg = Shellwords.split(msg)
    command = msg.shift
    case command
    when "enq"
      enq_handler(io, msg[0])
    when "enq-head"
      do_enq_head(io, msg)
    when "enq-cmd"
      enq_handler(io, { "command" => msg[0]})
    when "pause", "play", "play_pause"
      play_pause_handler(io, command)
    when "seek"
      do_seek(io, msg[0])
    when "clear"
      @queue.clear
      echo("clear")
      io.emit("OK")
    when "rg"
      rg_handler(io, msg)
    when "skip"
      skip_handler(io, msg)
    when "sink"
      sink_handler(io, msg)
    when "current"
      current_handler(io, msg)
    when "watch"
      @watchers[io] = true
      io.emit("OK")
    when "format"
      format_handler(io, msg)
    when "env"
      env_handler(io, msg)
    when "restart"
      restart_pipeline
      io.emit("OK")
    when "source"
      source_handler(io, msg)
    when "cd"
      chdir_handler(io, msg)
    when "pwd"
      io.emit(Dir.pwd)
    end
  end

  def event_loop_iter
    @srv.run_once do |io, msg| # readability handler, request/response
      case io
      when @sink_buf
        sink_iter
      when DTAS::UNIXAccepted
        client_iter(io, msg)
      when DTAS::Sigevent # signal received
        reap_iter
      else
        raise "BUG: unknown event: #{io.class} #{io.inspect} #{msg.inspect}"
      end
    end
  end

  def reap_iter
    DTAS::Process.reaper do |status, obj|
      warn [ :reap, obj, status ].inspect if $DEBUG
      obj.on_death(status) if obj.respond_to?(:on_death)
      case obj
      when @current
        next_source(@paused ? nil : @queue.shift)
      when DTAS::Sink # on unexpected sink death
        sink_death(obj, status)
      end
    end
    :wait_readable
  end

  def sink_death(sink, status)
    deleted = []
    @targets.delete_if do |t|
      if t.sink == sink
        deleted << t
      else
        false
      end
    end

    if deleted[0]
      warn("#{sink.name} died unexpectedly: #{status.inspect}")
      deleted.each { |t| drop_target(t) }
      __current_drop unless @targets[0]
      return # sink stays dead if it died unexpectedly
    end

    return unless sink.active

    if (@current || @queue[0]) && !@paused
      # we get here if source/sinks are all killed in restart_pipeline
      __sink_activate(sink)
      next_source(@queue.shift) unless @current
    end
  end

  # returns a wait_ctl arg for self
  def broadcast_iter(buf, targets)
    case rv = buf.broadcast(targets)
    when Array # array of blocked sinks
      # have sinks wake up the this buffer when they're writable
      trade_ctl = proc { @srv.wait_ctl(buf, :wait_readable) }
      rv.each do |dst|
        dst.on_writable = trade_ctl
        @srv.wait_ctl(dst, :wait_writable)
      end

      # this @sink_buf hibernates until trade_ctl is called
      # via DTAS::Sink#writable_iter
      :ignore
    else # :wait_readable or nil
      rv
    end
  end

  def bind
    @srv = DTAS::UNIXServer.new(@socket)
  end

  # only used on new installations where no sink exists
  def create_default_sink
    return unless @sinks.empty?
    s = DTAS::Sink.new
    s.name = "default"
    s.active = true
    @sinks[s.name] = s
  end

  # called when the player is leaving idle state
  def spawn_sinks(source_spec)
    return true if @targets[0]
    @sinks.each_value do |sink|
      sink.active or next
      next if sink.pid
      @targets.concat(sink.spawn(@format))
    end
    if @targets[0]
      @targets.sort_by! { |t| t.sink.prio }
      true
    else
      # fail, no active sink
      @queue.unshift(source_spec)
      false
    end
  end

  def try_file(*args)
    @sources.each do |src|
      rv = src.try(*args) and return rv
    end

    # keep going down the list until we find something
    while source_spec = @queue.shift
      @sources.each do |src|
        rv = src.try(*source_spec) and return rv
      end
    end
    echo "idle"
    nil
  end

  def next_source(source_spec)
    @current = nil
    if source_spec
      # restart sinks iff we were idle
      spawn_sinks(source_spec) or return

      case source_spec
      when String
        pending = try_file(source_spec) or return
        echo(%W(file #{pending.infile}))
      when Array
        pending = try_file(*source_spec) or return
        echo(%W(file #{pending.infile} #{pending.offset_samples}s))
      else
        pending = DTAS::Source::Cmd.new(source_spec["command"])
        echo(%W(command #{pending.command_string}))
      end

      dst = @sink_buf
      pending.dst_assoc(dst)
      pending.spawn(@format, @rg, out: dst.wr, in: "/dev/null")
      @current = pending
      @srv.wait_ctl(dst, :wait_readable)
    else
      stop_sinks if @sink_buf.inflight == 0
      echo "idle"
    end
  end

  def drop_target(target)
    @srv.wait_ctl(target, :delete)
    target.close
  end

  def stop_sinks
    @targets.each { |t| drop_target(t) }.clear
  end

  # only call on unrecoverable errors (or "skip")
  def __current_drop(src = @current)
    __buf_reset(src.dst) if src && src.pid
  end

  # pull data from sink_buf into @targets, source feeds into sink_buf
  def sink_iter
    wait_iter = broadcast_iter(@sink_buf, @targets)
    __current_drop if nil == wait_iter # sink error, stop source
    return wait_iter if @current

    # no source left to feed sink_buf, drain the remaining data
    sink_bytes = @sink_buf.inflight
    if sink_bytes > 0
      return wait_iter if @targets[0] # play what is leftover

      # discard the buffer if no sinks
      @sink_buf.discard(sink_bytes)
    end

    # nothing left inflight, stop the sinks until we have a source
    stop_sinks
    :ignore
  end

  # the main loop
  def run
    sev = DTAS::Sigevent.new
    @srv.wait_ctl(sev, :wait_readable)
    old_chld = trap(:CHLD) { sev.signal }
    create_default_sink
    next_source(@paused ? nil : @queue.shift)
    begin
      event_loop_iter
    rescue => e # just in case...
      warn "E: #{e.message} (#{e.class})"
      e.backtrace.each { |l| warn l }
    end while true
  ensure
    __current_requeue
    trap(:CHLD, old_chld)
    sev.close if sev
    # for state file
  end

  def close
    @srv = @srv.close if @srv
    @sink_buf.close!
    @state_file.dump(self, true) if @state_file
  end
end

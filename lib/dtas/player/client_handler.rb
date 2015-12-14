# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../xs'
require_relative '../parse_time'

# client protocol handling for -player
module DTAS::Player::ClientHandler # :nodoc:
  include DTAS::XS
  include DTAS::ParseTime

  # returns true on success, wait_ctl arg on error
  def set_bool(io, kv, v)
    case v
    when "false" then yield(false)
    when "true" then yield(true)
    else
      return io.emit("ERR #{kv} must be true or false")
    end
    true
  end

  def adjust_numeric(io, obj, k, v)
    negate = !!v.sub!(/\A-/, '')
    case v
    when %r{\A\+?\d*\.\d+\z}
      num = v.to_f
    when %r{\A\+?\d+\z}
      num = v.to_i
    else
      return io.emit("ERR #{k}=#{v} must be a float")
    end
    num = -num if negate

    if k.sub!(/\+\z/, '') # increment existing
      num += obj.__send__(k)
    elsif k.sub!(/-\z/, '') # decrement existing
      num = obj.__send__(k) - num
    # else # normal assignment
    end
    obj.__send__("#{k}=", num)
    true
  end

  # returns true on success, wait_ctl arg on error
  def set_int(io, kv, v, null_ok)
    case v
    when %r{\A-?\d+\z}
      yield(v.to_i)
    when ""
      null_ok or return io.emit("ERR #{kv} must be defined")
      yield(nil)
    else
      return io.emit("ERR #{kv} must an integer")
    end
    true
  end

  # returns true on success, wait_ctl arg on error
  def set_uint(io, kv, v, null_ok)
    case v
    when %r{\A\d+\z}
      yield(v.to_i)
    when %r{\A0x[0-9a-fA-F]+\z}i # hex
      yield(v.to_i(16))
    when ""
      null_ok or return io.emit("ERR #{kv} must be defined")
      yield(nil)
    else
      return io.emit("ERR #{kv} must an non-negative integer")
    end
    true
  end

  def __sink_activate(sink)
    return if sink.pid
    @targets.concat(sink.sink_spawn(@format))
    @targets.sort_by! { |t| t.sink.prio }
  end

  def drop_sink(sink)
    @targets.delete_if do |t|
      if t.sink == sink
        drop_target(t)
        true
      else
        false
      end
    end
  end

  # called to activate/deactivate a sink
  def __sink_switch(sink)
    if sink.active
      if @current
        # maybe it's still alive for now, but it's just being killed
        # do not reactivate it until we've reaped it
        if sink.pid
          drop_sink(sink)

          # we must restart @current if there's a moment we're target-less:
          __current_requeue unless @targets[0]
        else
          __sink_activate(sink)
        end
      end
    else
      drop_sink(sink)
    end
    # if we change any sinks, make sure the event loop watches it for
    # readability again, since we new sinks should be writable, and
    # we've stopped waiting on killed sinks
    @srv.wait_ctl(@sink_buf, :wait_readable)
  end

  def __sink_snapshot(sink)
    [ sink.command, sink.env, sink.pipe_size ].inspect
  end

  # returns a wait_ctl arg
  def dpc_sink(io, msg)
    name = msg[1]
    case msg[0]
    when "ls"
      io.emit(xs(@sinks.keys.sort))
    when "rm"
      sink = @sinks.delete(name) or return io.emit("ERR #{name} not found")
      drop_sink(sink)
      io.emit("OK")
    when "ed"
      sink = @sinks[name] || (new_sink = DTAS::Sink.new)

      # allow things that look like audio device names ("hw:1,0" , "/dev/dsp")
      # or variable names.
      sink.valid_name?(name) or return io.emit("ERR sink name invalid")

      sink.name = name
      active_before = sink.active
      before = __sink_snapshot(sink)

      # multiple changes may be made at once
      msg[2..-1].each do |kv|
        k, v = kv.split(/=/, 2)
        case k
        when %r{\Aenv\.([^=]+)\z}
          sink.env[$1] = v
        when %r{\Aenv#([^=]+)\z}
          v == nil or return io.emit("ERR unset env has no value")
          sink.env.delete($1)
        when "prio"
          rv = set_int(io, kv, v, false) { |i| sink.prio = i }
          rv == true or return rv
          @targets.sort_by! { |t| t.sink.prio } if sink.active
        when "nonblock", "active"
          rv = set_bool(io, kv, v) { |b| sink.__send__("#{k}=", b) }
          rv == true or return rv
        when "pipe_size"
          rv = set_uint(io, kv, v, true) { |u| sink.pipe_size = u }
          rv == true or return rv
        when "command" # nothing to validate, this could be "rm -rf /" :>
          sink.command = v.empty? ? DTAS::Sink::SINK_DEFAULTS["command"] : v
        end
      end

      @sinks[name] = new_sink if new_sink # no errors? it's a new sink!
      after = __sink_snapshot(sink)

      # start or stop a sink if its active= flag changed.  Additionally,
      # account for a crashed-but-marked-active sink.  The user may have
      # fixed the command to not crash it.
      if (active_before != sink.active) ||
         (sink.active && (!sink.pid || before != after))
        __sink_switch(sink)
      end
      io.emit("OK")
    when "cat"
      sink = @sinks[name] or return io.emit("ERR #{name} not found")
      io.emit(sink.to_hash.to_yaml)
    else
      io.emit("ERR unknown sink op #{msg[0]}")
    end
  end

  def bytes_decoded(src = @current)
    bytes = src.dst.bytes_xfer - src.dst_zero_byte
    bytes = bytes < 0 ? 0 : bytes # maybe negative in case of sink errors
  end

  # returns seek offset as an Integer in sample count
  def __seek_offset_adj(dir, offset)
    if offset.sub!(/s\z/, '')
      offset = offset.to_i
    else # time
      offset = @current.format.hhmmss_to_samples(offset)
    end
    n = __current_decoded_samples + (dir * offset)
    n = 0 if n < 0
    "#{n}s"
  end

  def __current_decoded_samples
    initial = @current.offset_samples
    decoded = @format.bytes_to_samples(bytes_decoded)
    decoded = out_samples(decoded, @format, @current.format)
    initial + decoded
  end

  def __current_requeue
    return unless @current

    # no need to requeue if we're already due to die
    return if @current.requeued
    @current.requeued = true

    dst = @current.dst
    # prepare to seek to the desired point based on the number of bytes which
    # passed through dst buffer we want the offset for the @current file,
    # which may have a different rate than our internal @format
    if @current.respond_to?(:infile)
      # this offset in the @current.format (not player @format)
      @queue.unshift([ @current.infile, "#{__current_decoded_samples}s" ])
    else
      # DTAS::Source::Cmd (hash), just rerun it
      @queue.unshift(@current.to_hsh)
    end
    # We also want to hard drop the buffer so we do not get repeated audio.
    __buf_reset(dst)
  end

  def out_samples(in_samples, infmt, outfmt)
    in_rate = infmt.rate
    out_rate = outfmt.rate
    return in_samples if in_rate == out_rate # easy!
    (in_samples * out_rate / in_rate.to_f).round
  end

  # returns the number of samples we expect from the source
  # this takes into account sample rate differences between the source
  # and internal player format
  def current_expect_samples(in_samples) # @current.samples
    out_samples(in_samples, @current.format, @format)
  end

  def dpc_rg(io, msg)
    return io.emit(@rg.to_hsh.to_yaml) if msg.empty?
    before = @rg.to_hsh
    msg.each do |kv|
      k, v = kv.split(/=/, 2)
      case k
      when "mode"
        case v
        when "off"
          @rg.mode = nil
        else
          DTAS::RGState::RG_MODE.include?(v) or
            return io.emit("ERR rg mode invalid")
          @rg.mode = v
        end
      when "fallback_track"
        rv = set_bool(io, kv, v) { |b| @rg.fallback_track = b }
        rv == true or return rv
      when %r{(?:gain_threshold|norm_threshold|
              preamp|norm_level|fallback_gain|volume)[+-]?\z}x
        rv = adjust_numeric(io, @rg, k, v)
        rv == true or return rv
      end
    end
    after = @rg.to_hsh
    __current_requeue if before != after
    io.emit("OK")
  end

  def active_sinks
    sinks = @targets.map(&:sink)
    sinks.uniq!
    sinks
  end

  # show current info about what's playing
  # returns non-blocking iterator retval
  def dpc_current(io, msg)
    tmp = {}
    if @current
      tmp["current"] = s = @current.to_hsh
      s["spawn_at"] = @current.spawn_at
      s["pid"] = @current.pid

      # this offset and samples in the player @format (not @current.format)
      decoded = @format.bytes_to_samples(bytes_decoded)
      if @current.respond_to?(:infile)
        initial = tmp["current_initial"] = @current.offset_samples
        initial = out_samples(initial, @current.format, @format)
        tmp["current_expect"] = current_expect_samples(s["samples"])
        s["format"] = @current.format.to_hash.delete_if { |_,v| v.nil? }
      else
        initial = 0
        tmp["current_expect"] = nil
        s["format"] = @format.to_hash.delete_if { |_,v| v.nil? }
      end
      tmp["current_offset"] = initial + decoded
    end
    tmp["current_inflight"] = @sink_buf.inflight
    tmp["format"] = @format.to_hash.delete_if { |_,v| v.nil? }
    tmp["bypass"] = @bypass.sort!
    tmp["paused"] = @paused
    rg = @rg.to_hsh
    tmp["rg"] = rg unless rg.empty?
    if @targets[0]
      sinks = active_sinks
      tmp["sinks"] = sinks.map! do |sink|
        h = sink.to_hsh
        h["pid"] = sink.pid
        h
      end
    end
    tmp['tracklist'] = @tl.to_hsh(false)
    io.emit(tmp.to_yaml)
  end

  def __buf_reset(buf) # buf is always @sink_buf for now
    @srv.wait_ctl(buf, :ignore)
    buf.buf_reset
    @srv.wait_ctl(buf, :wait_readable)
  end

  def dpc_skip(io, msg)
    __current_drop
    wall("skip")
    io.emit("OK")
  end

  def play_pause_handler(io, command)
    prev = @paused
    __send__("do_#{command}")
    io.emit({
      "paused" => {
        "before" => prev,
        "after" => @paused,
      }
    }.to_yaml)
  end

  def do_pause
    return if @paused
    wall("pause")
    @paused = true
    __current_requeue
  end

  def do_play
    # no wall, next_source will wall on new track
    @paused = false
    return if @current
    n = _next
    unless n
      @tl.reset
      n = _next
    end
    next_source(n)
  end

  def do_play_pause
    @paused ? do_play : do_pause
  end

  def seek_internal(cur, offset)
    if cur.requeued
      @queue[0][1] = offset
    else
      @queue.unshift([ cur.infile, offset ])
      cur.requeued = true
      __buf_reset(cur.dst) # trigger EPIPE
    end
  end

  def dpc_seek(io, msg)
    offset = msg[0]
    if @current
      if @current.respond_to?(:infile)
        begin
          if offset.sub!(/\A\+/, '')
            offset = __seek_offset_adj(1, offset)
          elsif offset.sub!(/\A-/, '')
            offset = __seek_offset_adj(-1, offset)
          # else: pass to sox directly
          end
        rescue ArgumentError
          return io.emit("ERR bad time format")
        end
        seek_internal(@current, offset)
      else
        return io.emit("ERR unseekable")
      end
    elsif @paused
      case file = @queue[0]
      when String
        @queue[0] = [ file, offset ]
      when Array
        file[1] = offset
      else
        return io.emit("ERR unseekable")
      end
    # unpaused case... what do we do?
    end
    io.emit("OK")
  end

  def restart_pipeline
    return if @paused
    __current_requeue
    stop_sinks
  end

  def dpc_restart(io, _)
    restart_pipeline
    io.emit('OK')
  end

  def dpc_format(io, msg)
    new_fmt = @format.dup
    msg.each do |kv|
      k, v = kv.split(/=/, 2)
      case k
      when "type"
        new_fmt.valid_type?(v) or return io.emit("ERR invalid file type")
        new_fmt.type = v
      when "channels", "bits", "rate"
        case v
        when "bypass"
          @bypass << k unless @bypass.include?(k)
        else
          rv = set_uint(io, kv, v, false) { |u| new_fmt.__send__("#{k}=", u) }
          rv == true or return rv
          @bypass.delete(k)
        end
      when "endian"
        new_fmt.valid_endian?(v) or return io.emit("ERR invalid endian")
        new_fmt.endian = v
      end
    end

    bypass_match!(new_fmt, @current.format) if @current

    if new_fmt != @format
      restart_pipeline # calls __current_requeue

      # we must assign this after __current_requeue since __current_requeue
      # relies on the old @format for calculation
      format_update!(new_fmt)
    end
    io.emit("OK")
  end

  def dpc_env(io, msg)
    if msg.empty?
      # this may fail for large envs due to SEQPACKET size restrictions
      # do we care?
      env = ENV.map do |k,v|
        "#{Shellwords.escape(k)}=#{Shellwords.escape(v)}"
      end.join(' ')
      return io.emit(env)
    end
    msg.each do |kv|
      case kv
      when %r{\A([^=]+)=(.*)\z}
        ENV[$1] = $2
      when %r{\A([^=]+)#}
        ENV.delete($1)
      else
        return io.emit("ERR bad env")
      end
    end
    io.emit("OK")
  end

  def dpc_source(io, msg)
    map = @source_map
    op = msg.shift
    case op
    when "restart"
      __current_requeue
      return io.emit("OK")
    when "ls"
      s = map.keys.sort { |a,b| map[a].tryorder <=> map[b].tryorder }
      return io.emit(s.join(' '))
    end

    name = msg.shift
    src = map[name] or return io.emit("ERR non-existent source name")
    case op
    when "cat"
      io.emit(src.to_source_cat.to_yaml)
    when "ed"
      before = src.to_state_hash.inspect
      sd = src.source_defaults
      msg.each do |kv|
        k, v = kv.split(/=/, 2)
        case k
        when "command"
          src.command = v.empty? ? sd[k] : v
        when %r{\Aenv\.([^=]+)\z}
          src.env[$1] = v
        when %r{\Aenv#([^=]+)\z}
          v == nil or return io.emit("ERR unset env has no value")
          src.env.delete($1)
        when "tryorder"
          rv = set_int(io, kv, v, true) { |i| src.tryorder = i || sd[k] }
          rv == true or return rv
          source_map_reload
        end
      end
      after = src.to_state_hash.inspect
      __current_requeue if before != after && @current.class == src.class
      io.emit("OK")
    else
      io.emit("ERR unknown source op")
    end
  end

  def dpc_cd(io, msg)
    msg.size == 1 or return io.emit("ERR usage: cd DIRNAME")
    begin
      Dir.chdir(msg[0])
    rescue => e
      return io.emit("ERR chdir: #{e.message}")
    end
    # wall(%W(cd msg[0])) # should we broadcast this?
    io.emit("OK")
  end

  def state_file_dump_async(io, sf)
    on_death = lambda { |_| @srv.wait_ctl(io, :wait_readable) }
    pid = fork do
      begin
        begin
          sf.dump(self)
          res = 'OK'
        rescue => e
          res = "ERR dumping to #{xs(sf.path)} #{e.message}"
        end
        io.to_io.send(res, Socket::MSG_EOR)
      ensure
        exit!(0)
      end
    end
    DTAS::Process::PIDS[pid] = on_death
  end

  def dpc_state(io, msg)
    case msg.shift
    when 'dump'
      dest = msg.shift
      if dest
        sf = DTAS::StateFile.new(dest, false)
      elsif @state_file
        sf = @state_file
        dest = sf.path
      else
        return io.emit("ERR no state file configured")
      end
      state_file_dump_async(io, sf)
      :ignore
    end
  end

  def _tl_skip
    @queue.clear
    __current_drop
  end

  def dpc_tl(io, msg)
    sub = msg.shift
    m = "_dpc_tl_#{sub.tr('-', '_')}"
    __send__(m, io, msg) if respond_to?(m)
  end

  def _dpc_tl_add(io, msg)
    path = msg.shift
    after_track_id = msg.shift
    after_track_id = after_track_id.to_i if after_track_id
    case set_as_current = msg.shift
    when 'true' then set_as_current = true
    when 'false', nil then set_as_current = false
    else
      return io.emit('ERR tl add PATH [after_track_id] [true|false]')
    end
    begin
      track_id = @tl.add_track(path, after_track_id, set_as_current)
      return io.emit('ERR FULL') unless track_id
    rescue ArgumentError => e
      return io.emit("ERR #{e.message}")
    end

    _tl_skip if set_as_current # if @current is playing, it will restart soon

    # start playing if we're currently idle
    next_source(_next) unless need_to_queue
    io.emit(track_id.to_s)
  end

  def _dpc_tl_repeat(io, msg)
    prev = @tl.repeat.to_s
    case msg.shift
    when 'true' then @tl.repeat = true
    when 'false' then @tl.repeat = false
    when '1' then @tl.repeat = 1
    when nil
    end
    io.emit("tl repeat #{prev}")
  end

  def _dpc_tl_shuffle(io, msg)
    prev = (!!@tl.shuffle).to_s
    v = msg.shift
    case v
    when 'debug' then return io.emit(@tl.shuffle.to_yaml) # TODO: remove
    when nil
    else
      set_bool(io, 'tl shuffle', v) { |b| @tl.shuffle = b }
    end
    io.emit("tl shuffle #{prev}")
  end

  def _dpc_tl_max(io, msg)
    prev = @tl.max
    case msg.shift
    when nil
    when %r{\A(\d[\d_]*)\z} then @tl.max = $1.to_i
    else
      return io.emit('ERR tl max must a non-negative integer')
    end
    io.emit("tl max #{prev}")
  end

  def _dpc_tl_remove(io, msg)
    track_id = msg.shift or return io.emit('ERR track_id not specified')
    track_id = track_id.to_i
    path = @tl.remove_track(track_id) or return io.emit('MISSING')
    rm = path.object_id

    # skip if we're removing the currently playing track
    if @current && @current.respond_to?(:infile) &&
       @current.infile.object_id == rm
      _tl_skip
    end
    # drop it from the queue, too, in case it just got requeued or paused
    @queue.delete_if { |t| Array === t && t[0].object_id == rm }
    io.emit(path)
  end

  def _dpc_tl_get(io, msg)
    res = @tl.get_tracks(msg.map!(&:to_i))
    res.map! { |tid, file| "#{tid}=#{file ? Shellwords.escape(file) : ''}" }
    io.emit("#{res.size} #{res.join(' ')}")
  end

  def _dpc_tl_tracks(io, msg)
    tracks = @tl.tracks
    io.emit("#{tracks.size} " << tracks.map!(&:to_s).join(' '))
  end

  def _dpc_tl_goto(io, msg)
    track_id = msg.shift or return io.emit('ERR track_id not specified')
    offset = msg.shift # may be nil
    if @tl.go_to(track_id.to_i, offset)
      _tl_skip
      next_source(_next) unless need_to_queue
      io.emit('OK')
    else
      io.emit('MISSING')
    end
  end

  def _dpc_tl_current(io, msg)
    track = @tl.cur_track
    io.emit(track ? track.to_path : 'NONE')
  end

  def _dpc_tl_current_id(io, msg)
    track = @tl.cur_track
    io.emit(track ? track.track_id.to_s : 'NONE')
  end

  def _dpc_tl_next(io, msg)
    _tl_skip
    io.emit('OK')
  end

  def _dpc_tl_prev(io, msg)
    @tl.previous!
    _tl_skip
    io.emit('OK')
  end

  def _dpc_tl_clear(io, msg)
    @tl.clear
    _tl_skip
    io.emit('OK')
  end

  def _dpc_tl_swap(io, msg)
    usage = 'ERR usage: "tl swap TRACK_ID_A TRACK_ID_B"'
    a_id = msg.shift or return io.emit(usage)
    b_id = msg.shift or return io.emit(usage)
    @tl.swap(a_id.to_i, b_id.to_i) or return io.emit('MISSING')
    io.emit('OK')
  end

  def __bp_prev_next(io, msg, cur, bp)
    case type = msg[1]
    when nil, "track"
      bp.keep_if(&:track?)
    when "pregap"
      bp.keep_if(&:pregap?)
    when "subindex" # any subindex
      bp.keep_if(&:subindex?)
    when /\A\d+\z/ # exact subindex match
      si = type.to_i
      bp.keep_if { |ci| ci.index == si }
    when "any" # anything goes
    else
      return io.emit("INVALID TYPE")
    end
    fmt = cur.format
    case msg[0]
    when "next"
      ds = __current_decoded_samples
      bp.each do |ci|
        next if ci.offset_samples(fmt) < ds
        seek_internal(cur, ci.offset)
        return io.emit("OK")
      end
      # go to the next (real) track if not found
      __current_drop
    when "prev"
      os = cur.offset_samples # where we currently started
      bp.reverse_each do |ci|
        next if ci.offset_samples(fmt) >= os
        seek_internal(cur, ci.offset)
        return io.emit("OK")
      end
      # offset may be nil/zero if we couldn't find a previous breakpoint
      seek_internal(cur, '0')
    end
    io.emit("OK")
  end

  def dpc_cue(io, msg)
    cur = @current
    if cur.respond_to?(:cuebreakpoints)
      bp = cur.cuebreakpoints
      case msg[0]
      when nil
        tmp = { "infile" => cur.infile, "cue" => bp.map(&:to_hash) }
        io.emit(tmp.to_yaml)
      when "next", "prev"
        return __bp_prev_next(io, msg, cur, bp)
      when "goto"
        index = msg[1] or return io.emit("NOINDEX")
        ci = bp[index.to_i] or return io.emit("BADINDEX")
        seek_internal(cur, ci.offset)
        return io.emit("OK")
      end
    else
      io.emit("NOCUE")
    end
  end

  def dpc_trim(io, msg)
    t = @trim
    case msg.size
    when 0 # OK
    when 1, 2
      case msg[0]
      when 'off'
        @trim = nil
      else
        begin
          tbeg = parse_time(msg[0])
          if tlen = msg[1]
            absolute = tlen.sub!(/\A=/, '') # 44:00 =44:55
            tlen = parse_time(tlen)
            tlen -= tbeg if absolute
          end
          @trim = [ tbeg, tlen ] # seconds as float, since we don't know rate
        rescue => e
          return io.emit("ERR #{e.message}")
        end
      end
      __current_requeue
    else
      return io.emit('ERR usage: trim [off|TBEG [TLEN]]')
    end
    io.emit(t ? t.map(&:to_s).join(' ') : 'off')
  end
end
# :startdoc:

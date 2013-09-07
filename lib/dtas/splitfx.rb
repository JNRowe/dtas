# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
# Unlike the stuff for dtas-player, dtas-splitfx is fairly tied to sox
# (but we may still pipe to ecasound or anything else)
require_relative '../dtas'
require_relative 'format'
require_relative 'process'
require_relative 'xs'
require 'tempfile'
class DTAS::SplitFX # :nodoc:
  CMD = 'sox "$INFILE" $COMMENTS $OUTFMT "$TRACKNUMBER.$SUFFIX" '\
        '$TRIMFX $RATEFX $DITHERFX'
  include DTAS::Process
  include DTAS::XS

  class T < Struct.new(:env, :comments, :tstart, :fade_in, :fade_out)
    def commit(next_track_samples)
      tlen = next_track_samples - tstart
      trimfx = "trim #{tstart}s #{tlen}s"
      if fade_in
        trimfx << " #{fade_in}"
      end
      if fade_out
        tmp = fade_out.dup
        fade_out_len = tmp.pop or
                         raise ArgumentError, "fade_out needs a time value"
        fade_type = tmp.pop # may be nil
        fade = " fade #{fade_type} 0 #{tlen}s #{fade_out_len}"
        trimfx << fade
      end
      env["TRIMFX"] = trimfx
    end
  end

  # vars:
  # $CHANNELS (input)
  # $BITS_PER_SAMPLE (input)
  def initialize
    @env = {}
    @comments = {}
    @track_first = 1
    @track_zpad = true
    @t2s = method(:t2s)
    @infile = nil
    @targets = {}
    @tracks = []
    @infmt = nil # wait until input is assigned
  end

  def _bool(hash, key)
    val = hash[key]
    case val
    when false, true then yield val
    when nil # ignore
    else
      raise TypeError, "'#{key}' must be boolean (true or false)"
    end
  end

  def import(hash, overrides = {})
    # merge overrides from the command-line
    overrides.each do |k,v|
      case v
      when Hash then hash[k] = (hash[k] || {}).merge(v)
      else
        hash[k] = v
      end
    end

    hash = hash.merge(overrides)
    case v = hash["track_zpad"]
    when Integer then @track_zpad = val
    else
      _bool(hash, "track_zpad") { |val| @track_zpad = val }
    end

    _bool(hash, "cdda_align") { |val| @t2s = method(val ? :t2s : :t2s_cdda) }

    case v = hash["track_first"]
    when Integer then @track_first = v
    when nil
    else
      raise TypeError, "'track_first' must be an integer"
    end

    %w(comments env targets).each do |key|
      case val = hash[key]
      when Hash then instance_variable_get("@#{key}").merge!(val)
      when nil
      else
        raise TypeError, "'#{key}' must be a hash"
      end
    end

    @targets.each_value do |thsh|
      case tfmt = thsh["format"]
      when Hash
        thsh["format"] = DTAS::Format.load(tfmt) unless tfmt.empty?
      end
    end

    load_input!(hash)
    load_tracks!(hash)
  end

  def load_input!(hash)
    @infile = hash["infile"] or raise ArgumentError, "'infile' not specified"
    if infmt = hash["infmt"] # rarely needed
      @infmt = DTAS::Format.load(infmt)
    else # likely
      @infmt = DTAS::Format.new
      @infmt.channels = qx(@env, %W(soxi -c #@infile)).to_i
      @infmt.rate = qx(@env, %W(soxi -r #@infile)).to_i
      # we don't care for type
    end
  end

  def generic_target(target = "flac")
    fmt = { "type" => target }
    { command: CMD, format: DTAS::Format.load(fmt) }
  end

  def spawn(target, t, dryrun = false)
    target = @targets[target] || generic_target(target)
    outfmt = target[:format]
    env = outfmt.to_env

    # set very high quality resampling if using 24-bit or higher output
    if outfmt.rate != @infmt.rate
      if outfmt.bits
        # set very-high resampling quality for 24-bit outputs
        quality = "-v" if outfmt.bits >= 24
      else
        # assume output bits matches input bits
        quality = "-v" if @infmt.bits >= 24
      end
      env["RATEFX"] = "rate #{quality} #{outfmt.rate}"
    end

    # add noise-shaped dither for 16-bit (sox manual seems to recommend this)
    outfmt.bits && outfmt.bits <= 16 and env["DITHERFX"] = "dither -s"
    comments = Tempfile.new(%W(dtas-splitfx-#{t.comments["TRACKNUMBER"]} .txt))
    comments.sync = true
    t.comments.each do |k,v|
      env[k] = v.to_s
      comments.puts("#{k}=#{v}")
    end
    env["COMMENTS"] = "--comment-file=#{comments.path}"
    env["INFILE"] = @infile
    env["OUTFMT"] = xs(outfmt.to_sox_arg)
    env["SUFFIX"] = outfmt.type
    env.merge!(t.env)

    command = target[:command]
    tmp = Shellwords.split(command).map do |arg|
      qx(env, "printf %s \"#{arg}\"")
    end
    echo = "echo #{xs(tmp)}"
    if dryrun
      command = echo
    else
      system(echo)
    end
    [ dtas_spawn(env, command, {}), comments ]
  end

  def load_tracks!(hash)
    tracks = hash["tracks"] or raise ArgumentError, "'tracks' not specified"
    tracks.each { |line| parse_track(Shellwords.split(line)) }

    fmt = "%d"
    case @track_zpad
    when true
      max = @track_first - 1 + @tracks.size
      fmt = "%0#{max.to_s.size}d"
    when Integer
      fmt = "%0#{@track_zpad}d"
    else
      fmt = "%d"
    end
    nr = @track_first
    @tracks.each do |t|
      t.comments["TRACKNUMBER"] = sprintf(fmt, nr)
      nr += 1
    end
  end

  # argv:
  #   [ 't', '0:05', 'track one', 'fade_in=t 4', '.comment=blah' ]
  #   [ 'stop', '1:00' ]
  def parse_track(argv)
    case cmd = argv.shift
    when "t"
      start_time = argv.shift
      title = argv.shift
      t = T.new
      t.tstart = @t2s.call(start_time)
      t.comments = @comments.dup
      t.comments["TITLE"] = title
      t.env = @env.dup

      argv.each do |arg|
        case arg
        when %r{\Afade_in=(.+)\z}
          # generate fade-in effect
          # $1 = "t 4" => "fade t 4 0 0"
          t.fade_in = "fade #$1 0 0"
        when %r{\Afade_out=(.+)\z} # $1 = "t 4" or just "4"
          t.fade_out = $1.split(/\s+/)
        when %r{\A\.(\w+)=(.+)\z} then t.comments[$1] = $2
        else
          raise ArgumentError, "unrecognized arg(s): #{xs(argv)}"
        end
      end

      prev = @tracks.last and prev.commit(t.tstart)
      @tracks << t
    when "stop"
      stop_time = argv.shift
      argv.empty? or raise ArgumentError, "stop does not take extra args"
      samples = @t2s.call(stop_time)
      prev = @tracks.last and prev.commit(samples)
    else
      raise ArgumentError, "unknown command: #{xs(Array(cmd))}"
    end
  end

  # like t2s, but align to CDDA sectors (75 frames per second)
  def t2s_cdda(time)
    time = time.dup
    frac = 0

    # fractions of a second, convert to samples based on sample rate
    # taking into account CDDA alignment
    if time.sub!(/\.(\d+)\z/, "")
      s = "0.#$1".to_f * @infmt.rate / 75
      frac = s.round * 75
    end

    # feed the rest to the normal function
    t2s(time) + frac
  end

  def t2s(time)
    @infmt.hhmmss_to_samples(time)
  end

  def run(target, jobs = 1, dryrun = false)
    fails = []
    tracks = @tracks.dup
    pids = {}
    jobs ||= tracks.size # jobs == nil => everything at once
    jobs.times.each do
      t = tracks.shift or break
      pid, tmp = spawn(target, t, dryrun)
      pids[pid] = [ t, tmp ]
    end

    while pids.size > 0
      pid, status = Process.waitpid2(-1)
      done = pids.delete(pid)
      if status.success?
        if t = tracks.shift
          pid, tmp = spawn(target, t, dryrun)
          pids[pid] = [ t, tmp ]
        end
        puts "DONE #{done[0].inspect}" if $DEBUG
        done[1].close!
      else
        fails << [ t, status ]
      end
    end

    return true if fails.empty? && tracks.empty?
    fails.each do |(_t,s)|
      warn "FAIL #{s.inspect} #{_t.inspect}"
    end
    false
  end
end

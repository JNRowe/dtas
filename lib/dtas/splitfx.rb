# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
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
        '$TRIMFX $FX $RATEFX $DITHERFX'
  include DTAS::Process
  include DTAS::XS
  attr_reader :infile, :env

  class Skip < Struct.new(:tstart) # :nodoc:
    def commit(_)
      # noop
    end
  end

  class T < Struct.new(:env, :comments, :tstart, :fade_in, :fade_out) # :nodoc:
    def commit(advance_track_samples)
      tlen = advance_track_samples - tstart
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
    @track_start = 1
    @track_zpad = true
    @t2s = method(:t2s)
    @infile = nil
    @targets = {
      "flac-cdda" => {
        "command" => CMD,
        "format" => {
          "bits" => 16,
          "rate" => 44100,
          "type" => "flac",
          "channels" => 2,
        },
      },
      "opusenc" => {
        "command" => 'sox "$INFILE" $COMMENTS $OUTFMT - ' \
           '$TRIMFX $FX $RATEFX $DITHERFX | opusenc --music ' \
           '--raw-bits $BITS_PER_SAMPLE ' \
           '$OPUSENC_BITRATE --raw-rate $RATE --raw-chan $CHANNELS ' \
           '--raw-endianness $ENDIAN_OPUSENC ' \
           '$OPUSENC_COMMENTS ' \
           '- $TRACKNUMBER.opus',
        "format" => {
          "bits" => 16,
          "rate" => 48000,
          "type" => "s16",
          "channels" => 2,
        },
      },
    }
    @tracks = []
    @infmt = nil # wait until input is assigned
    @cuebp = nil # for playback
    @command = nil # top-level, for playback
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

    case v = hash["track_zpad"]
    when Integer then @track_zpad = val
    else
      _bool(hash, "track_zpad") { |val| @track_zpad = val }
    end

    _bool(hash, "cdda_align") { |val| @t2s = method(val ? :t2s : :t2s_cdda) }

    case v = hash["track_start"]
    when Integer then @track_start = v
    when nil
    else
      raise TypeError, "'track_start' must be an integer"
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
    @command = hash["command"] # nil by default
  end

  def load_input!(hash)
    @infile = hash["infile"] or raise ArgumentError, "'infile' not specified"
    if infmt = hash["infmt"] # rarely needed
      @infmt = DTAS::Format.load(infmt)
    else # likely
      @infmt = DTAS::Format.from_file(@env, @infile)
    end
  end

  def generic_target(target = "flac")
    outfmt = @infmt.dup
    outfmt.type = target
    { "command" => CMD, "format" => outfmt }
  end

  def spawn(target, t, opts)
    target = @targets[target] || generic_target(target)
    outfmt = target["format"]

    # default format:
    unless outfmt
      outfmt = @infmt.dup
      outfmt.type = "flac"
    end
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
    if opts[:no_dither]
      env["SOX_OPTS"] = "#{ENV["SOX_OPTS"]} -D"
    else outfmt.bits && outfmt.bits <= 16
      env["DITHERFX"] = "dither -s"
    end
    comments = Tempfile.new(%W(dtas-splitfx-#{t.comments["TRACKNUMBER"]} .txt))
    comments.sync = true
    t.comments.each do |k,v|
      env[k] = v.to_s
      comments.puts("#{k}=#{v}")
    end
    env["COMMENTS"] = "--comment-file=#{comments.path}"
    infile_env(env, @infile)
    env["OUTFMT"] = xs(outfmt.to_sox_arg)
    env["SUFFIX"] = outfmt.type
    env.merge!(t.env)

    command = target["command"]

    # if a default dtas-player command is set, use that.
    # we'll clobber our default environment since we assume play_cmd
    # already takes those into account.  In other words, use our
    # target-specific commands like a dtas-player sink:
    #   @command | (INFILE= FX= TRIMFX=; target['command'])
    if player_cmd = @command
      sub_env = { 'INFILE' => '-', 'FX' => '', 'TRIMFX' => '' }
      sub_env_s = sub_env.inject("") { |s,(k,v)| s << "#{k}=#{v} " }
      command = "#{player_cmd} | (#{sub_env_s}; #{command})"
      show_cmd = [ _expand_cmd(env, player_cmd), '|', '(', "#{sub_env_s};",
                   _expand_cmd(env.merge(sub_env), command), ')' ].flatten
    else
      show_cmd = _expand_cmd(env, command)
    end

    echo = "echo #{xs(show_cmd)}"
    if opts[:dryrun]
      command = echo
    else
      system(echo) unless opts[:silent]
    end

    # pgroup: false so Ctrl-C on command-line will immediately stop everything
    [ dtas_spawn(env, command, pgroup: false), comments ]
  end

  def load_tracks!(hash)
    tracks = hash["tracks"] or raise ArgumentError, "'tracks' not specified"
    tracks.each { |line| parse_track(Shellwords.split(line)) }

    fmt = "%d"
    case @track_zpad
    when true
      max = @track_start - 1 + @tracks.size
      fmt = "%0#{max.to_s.size}d"
    when Integer
      fmt = "%0#{@track_zpad}d"
    end
    nr = @track_start
    @tracks.delete_if do |t|
      case t
      when Skip
        true
      else
        t.comments["TRACKNUMBER"] = sprintf(fmt, nr)
        nr += 1
        false
      end
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
    when "skip"
      stop_time = argv.shift
      argv.empty? or raise ArgumentError, "skip does not take extra args"
      s = Skip.new
      s.tstart = @t2s.call(stop_time)
      # s.comments = {}
      # s.env = {}
      prev = @tracks.last or raise ArgumentError, "no tracks to skip"
      prev.commit(s.tstart)
      @tracks << s
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

  def run(target, opts = {})
    fails = []
    tracks = @tracks.dup
    pids = {}
    jobs = opts[:jobs] || tracks.size # jobs == nil => everything at once
    jobs.times.each do
      t = tracks.shift or break
      pid, tmp = spawn(target, t, opts)
      pids[pid] = [ t, tmp ]
    end

    while pids.size > 0
      pid, status = Process.waitpid2(-1)
      done = pids.delete(pid)
      if status.success?
        if t = tracks.shift
          pid, tmp = spawn(target, t, opts)
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

  def cuebreakpoints
    rv = @cuebp and return rv
    require_relative 'cue_index'
    @cuebp = @tracks.map { |t| DTAS::CueIndex.new(1, "#{t.tstart}s") }
  end

  def infile_env(env, infile)
    env["INFILE"] = infile
    env["INDIR"], env["INBASE"] = File.split(File.expand_path(infile))
  end

  def _expand_cmd(env, command)
    Shellwords.split(command).map do |arg|
      qx(env, "printf %s \"#{arg}\"")
    end
  end
end

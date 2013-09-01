# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../../dtas'
require_relative '../source'
require_relative '../replaygain'
require_relative '../xs'
require_relative 'file'

# Common code for libav (avconv/avprobe) and ffmpeg (and ffprobe)
# TODO: newer versions of both *probes support JSON, which will be easier to
# parse.  However, the packaged libav version in Debian 7.0 does not
# support JSON, so we have an ugly parser...
module DTAS::Source::AvFfCommon # :nodoc:
  include DTAS::Source::File
  include DTAS::XS
  AStream = Struct.new(:duration, :channels, :rate)
  AV_FF_TRYORDER = 1

  attr_reader :precision # always 32
  attr_reader :format

  def try(infile, offset = nil)
    rv = source_file_dup(infile, offset)
    rv.av_ff_ok? or return
    rv
  end

  def __parse_astream(cmd, stream)
    stream =~ /^codec_type=audio$/ or return
    as = AStream.new
    index = nil
    stream =~ /^index=(\d+)\s*$/nm and index = $1.to_i
    stream =~ /^duration=([\d\.]+)\s*$/nm and as.duration = $1.to_f
    stream =~ /^channels=(\d)\s*$/nm and as.channels = $1.to_i
    stream =~ /^sample_rate=([\d\.]+)\s*$/nm and as.rate = $1.to_i
    index or raise "BUG: no audio index from #{xs(cmd)}"
    yield(index, as)
  end

  def probe_ok?(status, err_str)
    return false if Process::Status === status
    return false if err_str =~ /Unable to find a suitable output format for/
    true
  end

  def av_ff_ok?
    @duration = nil
    @format = DTAS::Format.new
    @format.bits = 32 # always, since we still use the "sox" format
    @comments = {}
    @astreams = []

    # needed for VOB and other formats which scatter metadata all over the
    # place and
    @probe_harder = nil
    incomplete = []
    prev_cmd = []

    begin # loop
      cmd = %W(#@av_ff_probe)

      # using the max known duration as a analyzeduration seems to work
      # for the few VOBs I've tested, but seeking is still broken.
      max_duration = 0
      incomplete.each do |as|
        as && as.duration or next
        max_duration = as.duration if as.duration > max_duration
      end
      if max_duration > 0
        usec = max_duration.round * 1000000
        usec = "2G" if usec >= 0x7fffffff # limited to INT_MAX :<
        @probe_harder = %W(-analyzeduration #{usec} -probesize 2G)
        cmd.concat(@probe_harder)
      end
      cmd.concat(%W(-show_streams -show_format #@infile))
      break if cmd == prev_cmd

      err = ""
      s = qx(@env, cmd, err_str: err, no_raise: true)
      return false unless probe_ok?(s, err)
      s.scan(%r{^\[STREAM\]\n(.*?)\n\[/STREAM\]\n}mn) do |_|
        __parse_astream(cmd, $1) do |index, as|
          # incomplete streams may have zero channels
          if as.channels > 0 && as.rate > 0
            @astreams[index] = as
            incomplete[index] = nil
          else
            incomplete[index] = as
          end
        end
      end
      prev_cmd = cmd
    end while incomplete.compact[0]

    s.scan(%r{^\[FORMAT\]\n(.*?)\n\[/FORMAT\]\n}m) do |_|
      f = $1
      f =~ /^duration=([\d\.]+)\s*$/nm and @duration = $1.to_f
      # TODO: multi-line/multi-value/repeated tags
      f.gsub!(/^TAG:([^=]+)=(.*)$/ni) { |_| @comments[$1.upcase] = $2 }
    end
    ! @astreams.compact.empty?
  end

  def sspos(offset)
    offset =~ /\A(\d+)s\z/ or return "-ss #{offset}"
    samples = $1.to_f
    sprintf("-ss %0.9g", samples / @format.rate)
  end

  def select_astream(as)
    @format.channels = as.channels
    @format.rate = as.rate

    # favor the duration of the stream we're playing instead of
    # duration we got from [FORMAT].  However, some streams may not have
    # a duration and only have it in [FORMAT]
    @duration = as.duration if as.duration
  end

  def amap_fallback
    @astreams.each_with_index do |as, index|
      as or next
      select_astream(as)
      warn "no suitable audio stream in #@infile, trying stream=#{index}"
      return "-map 0:#{index}"
    end
    raise "BUG: no audio stream in #@infile"
  end

  def spawn(player_format, rg_state, opts)
    raise "BUG: #{self.inspect}#spawn called twice" if @to_io
    amap = nil

    # try to find an audio stream which matches our channel count
    # we need to set @format for sspos() down below
    @astreams.each_with_index do |as, i|
      if as && as.channels == player_format.channels
        select_astream(as)
        amap = "-map 0:#{i}"
      end
    end

    # fall back to the first audio stream
    # we must call select_astream before sspos
    amap ||= amap_fallback

    e = @env.merge!(player_format.to_env)

    e["PROBE"] = @probe_harder ? @probe_harder.join(' ') : nil
    # make sure these are visible to the source command...
    e["INFILE"] = @infile
    e["AMAP"] = amap
    e["SSPOS"] = @offset ? sspos(@offset) : nil
    e["RGFX"] = rg_state.effect(self) || nil
    e.merge!(@rg.to_env) if @rg

    @pid = dtas_spawn(e, command_string, opts)
  end

  # This is the number of samples according to the samples in the source
  # file itself, not the decoded output
  def samples
    @samples ||= (@duration * @format.rate).round
  rescue
    0
  end

  def to_hsh
    sd = source_defaults
    to_hash.delete_if { |k,v| v == sd[k] }
  end
end

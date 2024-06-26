# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../../dtas'
require_relative '../source'
require_relative '../replaygain'
require_relative '../xs'
require_relative 'file'

# Common code for ffmpeg/ffprobe and the abandoned libav (avconv/avprobe).
# TODO: newer versions of both *probes support JSON, which will be easier
# to parse.  libav is abandoned, nowadays, and Debian only packages
# ffmpeg+ffprobe nowadays.
module DTAS::Source::AvFfCommon # :nodoc:
  include DTAS::Source::File
  include DTAS::XS
  AStream = Struct.new(:duration, :channels, :rate)
  AV_FF_TRYORDER = 1

  attr_reader :precision # always 32
  attr_reader :format
  attr_reader :duration

  CACHE_KEYS = [ :@duration, :@probe_harder, :@comments, :@astreams,
                 :@format ].freeze

  def mcache_lookup(infile)
    (@mcache ||= DTAS::Mcache.new).lookup(infile) do |input, dst|
      tmp = source_file_dup(infile, nil, nil)
      tmp.av_ff_ok? or return nil
      CACHE_KEYS.each { |k| dst[k] = tmp.instance_variable_get(k) }
      dst
    end
  end

  def try(infile, offset = nil, trim = nil)
    ent = mcache_lookup(infile) or return
    ret = source_file_dup(infile, offset, trim)
    CACHE_KEYS.each { |k| ret.instance_variable_set(k, ent[k]) }
    ret
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

      err = "".b
      begin
        s = qx(@env, cmd, err_str: err, no_raise: true)
      rescue Errno::ENOENT # avprobe/ffprobe not installed
        return false
      end
      return false unless probe_ok?(s, err)

      # old avprobe
      [ %r{^\[STREAM\]\n(.*?)\n\[/STREAM\]\n}mn,
        %r{^\[streams\.stream\.\d+\]\n(.*?)\n\n}mn ].each do |re|
        s.scan(re) do |_|
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
      end

      prev_cmd = cmd
    end while incomplete.compact[0]

    enc = Encoding.default_external # typically Encoding::UTF_8
    # old avprobe
    s.scan(%r{^\[FORMAT\]\n(.*?)\n\[/FORMAT\]\n}m) do |_|
      f = $1.dup
      f =~ /^duration=([\d\.]+)\s*$/nm and @duration = $1.to_f
      # TODO: multi-line/multi-value/repeated tags
      f.gsub!(/^TAG:([^=]+)=(.*)$/ni) { |_|
        @comments[-DTAS.try_enc($1.upcase, enc)] = $2
      }
    end

    # new avprobe
    s.scan(%r{^\[format\.tags\]\n(.*?)\n\n}m) do |_|
      f = $1.dup
      f.gsub!(/^([^=]+)=(.*)$/ni) { |_|
        @comments[-DTAS.try_enc($1.upcase, enc)] = $2
      }
    end
    s.scan(%r{^\[format\]\n(.*?)\n\n}m) do |_|
      f = $1.dup
      f =~ /^duration=([\d\.]+)\s*$/nm and @duration = $1.to_f
    end
    comments.each do |k,v|
      v.chomp!
      comments[k] = -DTAS.try_enc(v, enc)
    end

    # ffprobe always uses "track", favor FLAC convention "TRACKNUMBER":
    if @comments['TRACK'] && !@comments['TRACKNUMBER']
      @comments['TRACKNUMBER'] = @comments.delete('TRACK')
    end

    ! @astreams.compact.empty?
  end

  def sspos
    return unless @offset || @trim
    off = offset_samples / @format.rate.to_f
    sprintf('-ss %0.9g', off)
  end

  def av_ff_trimfx # for sox
    return unless @trim
    tbeg, tlen = @trim # Floats
    tend = tbeg + tlen
    off = offset_samples / @format.rate.to_f
    tlen = tend - off
    tlen = 0 if tlen < 0
    sprintf('trim 0 %0.9g', tlen)
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

  def src_spawn(player_format, rg_state, opts)
    raise "BUG: #{self.inspect}#src_spawn called twice" if @to_io
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
    e["SSPOS"] = sspos
    e["RGFX"] = rg_state.effect(self) || nil
    e["TRIMFX"] = av_ff_trimfx
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

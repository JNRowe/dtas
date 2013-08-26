# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../../dtas'
require_relative '../source'
require_relative '../replaygain'
require_relative 'file'

module DTAS::Source::AvFfCommon
  include DTAS::Source::File
  AStream = Struct.new(:duration, :channels, :rate)
  AV_FF_TRYORDER = 1

  attr_reader :precision # always 32
  attr_reader :format

  def try(infile, offset = nil)
    rv = source_file_dup(infile, offset)
    rv.av_ff_ok? or return
    rv
  end

  def av_ff_ok?
    @duration = nil
    @format = DTAS::Format.new
    @format.bits = 32 # always, since we still use the "sox" format
    @comments = {}
    @astreams = []
    cmd = %W(#@av_ff_probe -show_streams -show_format #@infile)
    err = ""
    s = qx(@env, cmd, err_str: err, no_raise: true)
    return false if Process::Status === s
    return false if err =~ /Unable to find a suitable output format for/
    s.scan(%r{^\[STREAM\]\n(.*?)\n\[/STREAM\]\n}m) do |_|
      stream = $1
      if stream =~ /^codec_type=audio$/
        as = AStream.new
        index = nil
        stream =~ /^index=(\d+)\s*$/m and index = $1.to_i
        stream =~ /^duration=([\d\.]+)\s*$/m and as.duration = $1.to_f
        stream =~ /^channels=(\d)\s*$/m and as.channels = $1.to_i
        stream =~ /^sample_rate=([\d\.]+)\s*$/m and as.rate = $1.to_i
        index or raise "BUG: no audio index from #{Shellwords.join(cmd)}"

        # some streams have zero channels
        @astreams[index] = as if as.channels > 0 && as.rate > 0
      end
    end
    s.scan(%r{^\[FORMAT\]\n(.*?)\n\[/FORMAT\]\n}m) do |_|
      f = $1
      f =~ /^duration=([\d\.]+)\s*$/m and @duration = $1.to_f
      # TODO: multi-line/multi-value/repeated tags
      f.gsub!(/^TAG:([^=]+)=(.*)$/i) { |_| @comments[$1.upcase] = $2 }
    end
    ! @astreams.empty?
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
      return "-map 0:#{i}"
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
  end

  def to_hsh
    sd = source_defaults
    to_hash.delete_if { |k,v| v == sd[k] }
  end
end

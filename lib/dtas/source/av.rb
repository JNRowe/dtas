# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../../dtas'
require_relative '../source'
require_relative '../replaygain'

# this is usually one input file
class DTAS::Source::Av # :nodoc:
  require_relative 'file'

  include DTAS::Source::File

  AStream = Struct.new(:duration, :channels, :rate)

  AV_DEFAULTS = COMMAND_DEFAULTS.merge(
    "command" =>
      'avconv -v error $SSPOS -i "$INFILE" $AMAP -f sox - |' \
      'sox -p $SOXFMT - $RGFX',
    "comments" => nil,
  )

  attr_reader :precision # always 32
  attr_reader :format

  def self.try(infile, offset = nil)
    err = ""
    DTAS::Process.qx(%W(avprobe #{infile}), err: err)
    return if err =~ /Unable to find a suitable output format for/
    new(infile, offset)
  rescue
  end

  def initialize(infile, offset = nil)
    command_init(AV_DEFAULTS)
    source_file_init(infile, offset)
    @precision = 32 # this still goes through sox, which is 32-bit
    do_avprobe
  end

  def do_avprobe
    @duration = nil
    @format = DTAS::Format.new
    @format.bits = @precision
    @comments = {}
    err = ""
    s = qx(%W(avprobe -show_streams -show_format #@infile), err: err)
    @astreams = []
    s.scan(%r{^\[STREAM\]\n(.*?)\n\[/STREAM\]\n}m) do |_|
      stream = $1
      # XXX what to do about multiple streams?
      if stream =~ /^codec_type=audio$/
        as = AStream.new
        index = nil
        stream =~ /^index=(\d+)\s*$/m and index = $1.to_i
        stream =~ /^duration=([\d\.]+)\s*$/m and as.duration = $1.to_f
        stream =~ /^channels=(\d)\s*$/m and as.channels = $1.to_i
        stream =~ /^sample_rate=([\d\.]+)\s*$/m and as.rate = $1.to_i
        @astreams[index] = as if as.channels > 0 && as.rate > 0
      end
    end
    s.scan(%r{^\[FORMAT\]\n(.*?)\n\[/FORMAT\]\n}m) do |_|
      f = $1
      f =~ /^duration=([\d\.]+)\s*$/m and @duration = $1.to_f
      # TODO: multi-line/multi-value/repeated tags
      f.gsub!(/^TAG:([^=]+)=(.*)$/i) { |_| @comments[$1.upcase] = $2 }
    end
  end

  def sspos(offset)
    offset =~ /\A(\d+)s\z/ or return "-ss #{offset}"
    samples = $1.to_f
    sprintf("-ss %0.9g", samples / @format.rate)
  end

  def spawn(player_format, rg_state, opts)
    raise "BUG: #{self.inspect}#spawn called twice" if @to_io
    amap = nil
    found_as = nil

    # try to find an audio stream which matches our channel count
    # we need to set @format for sspos() down below
    @astreams.each_with_index do |as, index|
      if as && as.channels == player_format.channels
        @format.channels = as.channels
        @format.rate = as.rate
        found_as = as
        amap = "-map 0:#{index}"
      end
    end
    unless found_as
      first_as = @astreams.compact[0]
      if first_as
        @format.channels = found_as.channels
        @format.rate = found_as.rate
      end
    end
    e = player_format.to_env
    e["INFILE"] = @infile
    e["AMAP"] = amap

    # make sure these are visible to the "current" command...
    @env["SSPOS"] = @offset ? sspos(@offset) : nil
    @env["RGFX"] = rg_state.effect(self) || nil
    e.merge!(@rg.to_env) if @rg

    @pid = dtas_spawn(e.merge!(@env), command_string, opts)
  end


  # This is the number of samples according to the samples in the source
  # file itself, not the decoded output
  def samples
    @samples ||= (@duration * @format.rate).round
  end

  def to_hsh
    to_hash.delete_if { |k,v| v == AV_DEFAULTS[k] }
  end
end

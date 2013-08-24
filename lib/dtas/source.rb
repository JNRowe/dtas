# -*- encoding: binary -*-
# :stopdoc:
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'command'
require_relative 'format'
require_relative 'replaygain'
require_relative 'process'
require_relative 'serialize'

# this is usually one input file
class DTAS::Source
  attr_reader :infile
  attr_reader :offset
  require_relative 'source/common'
  require_relative 'source/mp3'

  include DTAS::Command
  include DTAS::Process
  include DTAS::Source::Common
  include DTAS::Source::Mp3

  SOURCE_DEFAULTS = COMMAND_DEFAULTS.merge(
    "command" => 'exec sox "$INFILE" $SOXFMT - $TRIMFX $RGFX',
    "comments" => nil,
  )

  SIVS = %w(infile comments command env)

  def initialize(infile, offset = nil)
    command_init(SOURCE_DEFAULTS)
    @format = nil
    @infile = infile
    @offset = offset
    @comments = nil
    @samples = nil
  end

  # this exists mainly to make the mpris interface easier, but it's not
  # necessary, the mpris interface also knows the sample rate
  def offset_us
    (offset_samples / format.rate.to_f) * 1000000
  end

  # returns any offset in samples (relative to the original source file),
  # likely zero unless seek was used
  def offset_samples
    return 0 unless @offset
    case @offset
    when /\A\d+s\z/
      @offset.to_i
    else
      format.hhmmss_to_samples(@offset)
    end
  end

  def precision
    qx(%W(soxi -p #@infile), err: "/dev/null").to_i # sox.git f4562efd0aa3
  rescue # fallback to parsing the whole output
    s = qx(%W(soxi #@infile), err: "/dev/null")
    s =~ /Precision\s+:\s*(\d+)-bit/
    v = $1.to_i
    return v if v > 0
    raise TypeError, "could not determine precision for #@infile"
  end

  def format
    @format ||= begin
      fmt = DTAS::Format.new
      fmt.from_file(@infile)
      fmt.bits ||= precision
      fmt
    end
  end

  # A user may be downloading the file and start playing
  # it before the download completes, this refreshes
  def samples!
    @samples = nil
    samples
  end

  # This is the number of samples according to the samples in the source
  # file itself, not the decoded output
  def samples
    @samples ||= qx(%W(soxi -s #@infile)).to_i
  rescue => e
    warn e.message
    0
  end

  # just run soxi -a
  def __load_comments
    tmp = {}
    case @infile
    when String
      err = ""
      cmd = %W(soxi -a #@infile)
      begin
        qx(cmd, err: err).split(/\n/).each do |line|
          key, value = line.split(/=/, 2)
          key && value or next
          # TODO: multi-line/multi-value/repeated tags
          tmp[key.upcase] = value
        end
      rescue => e
        if /FAIL formats: no handler for file extension/ =~ err
          warn("#{xs(cmd)}: #{err}")
        else
          warn("#{e.message} (#{e.class})")
        end
        # TODO: fallbacks
      end
    end
    tmp
  end

  def comments
    @comments ||= __load_comments
  end

  def replaygain
    DTAS::ReplayGain.new(comments) || DTAS::ReplayGain.new(mp3gain_comments)
  end

  def spawn(format, rg_state, opts)
    raise "BUG: #{self.inspect}#spawn called twice" if @to_io
    e = format.to_env
    e["INFILE"] = @infile

    # make sure these are visible to the "current" command...
    @env["TRIMFX"] = @offset ? "trim #@offset" : nil
    @env["RGFX"] = rg_state.effect(self) || nil

    @pid = dtas_spawn(e.merge!(@env), command_string, opts)
  end

  def to_hsh
    to_hash.delete_if { |k,v| v == SOURCE_DEFAULTS[k] }
  end

  def to_hash
    rv = ivars_to_hash(SIVS)
    rv["samples"] = samples
    rv
  end
end

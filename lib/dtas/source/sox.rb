# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../../dtas'
require_relative '../source'
require_relative '../replaygain'

# this is usually one input file
class DTAS::Source::Sox # :nodoc:
  require_relative 'file'

  include DTAS::Source::File

  SOX_DEFAULTS = COMMAND_DEFAULTS.merge(
    "command" => 'exec sox "$INFILE" $SOXFMT - $TRIMFX $RGFX',
  )

  def initialize
    command_init(SOX_DEFAULTS)
  end

  def try(infile, offset = nil)
    err = ""
    qx(@env, %W(soxi #{infile}), err_str: err, no_raise: true)
    return if err =~ /soxi FAIL formats:/
    rv = dup
    rv.source_file_init(infile, offset)
    rv
  end

  def precision
    qx(@env, %W(soxi -p #@infile), err: "/dev/null").to_i # sox.git f4562efd0aa3
  rescue # fallback to parsing the whole output
    s = qx(@env, %W(soxi #@infile), err: "/dev/null")
    s =~ /Precision\s+:\s*(\d+)-bit/
    v = $1.to_i
    return v if v > 0
    raise TypeError, "could not determine precision for #@infile"
  end

  def format
    @format ||= begin
      fmt = DTAS::Format.new
      path = @infile
      fmt.channels = qx(@env, %W(soxi -c #{path})).to_i
      fmt.type = qx(@env, %W(soxi -t #{path})).strip
      fmt.rate = qx(@env, %W(soxi -r #{path})).to_i
      fmt.bits ||= precision
      fmt
    end
  end

  # This is the number of samples according to the samples in the source
  # file itself, not the decoded output
  def samples
    @samples ||= qx(@env, %W(soxi -s #@infile)).to_i
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
        qx(@env, cmd, err_str: err).split(/\n/).each do |line|
          key, value = line.split(/=/, 2)
          key && value or next
          # TODO: multi-line/multi-value/repeated tags
          tmp[key.upcase] = value
        end
      rescue => e
        if /FAIL formats: no handler for file extension/ =~ err
          warn("#{Shellwords.escape(cmd)}: #{err}")
        else
          warn("#{e.message} (#{e.class})")
        end
      end
    end
    tmp
  end

  def spawn(player_format, rg_state, opts)
    raise "BUG: #{self.inspect}#spawn called twice" if @to_io
    e = @env.merge!(player_format.to_env)
    e["INFILE"] = @infile

    # make sure these are visible to the "current" command...
    e["TRIMFX"] = @offset ? "trim #@offset" : nil
    e["RGFX"] = rg_state.effect(self) || nil
    e.merge!(@rg.to_env) if @rg

    @pid = dtas_spawn(e, command_string, opts)
  end

  def to_hsh
    to_hash.delete_if { |k,v| v == SOX_DEFAULTS[k] }
  end
end

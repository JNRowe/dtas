# Copyright (C) 2013-2019 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
# encoding: binary
require_relative '../../dtas'
require_relative '../source'
require_relative '../replaygain'
require_relative '../xs'

# this is usually one input file
class DTAS::Source::Sox # :nodoc:
  require_relative 'file'

  include DTAS::Source::File
  include DTAS::XS
  extend DTAS::XS

  SOX_DEFAULTS = COMMAND_DEFAULTS.merge(
    "command" => 'exec sox "$INFILE" $SOXFMT - $TRIMFX $RGFX',
    "tryorder" => 0,
  )

  def soxi_failed(infile, msg)
    return if @last_failed == infile
    @last_failed = infile
    case msg
    when Process::Status then msg = "failed with #{msg.exitstatus}"
    when 0 then msg = 'detected zero samples'
    end
    warn("soxi #{infile}: #{msg}\n")
  end

  def initialize(mcache = nil)
    @mcache = nil
    @last_failed = nil
    command_init(SOX_DEFAULTS)
  end

  def mcache_lookup(infile)
    (@mcache ||= DTAS::Mcache.new).lookup(infile) do |input, dst|
      err = ''.b
      out = qx(@env.dup, %W(soxi #{input}), err_str: err, no_raise: true)
      return soxi_failed(infile, out) if Process::Status === out
      return soxi_failed(infile, err) if err =~ /soxi FAIL formats:/
      out =~ /^Duration\s*:[^=]*= (\d+) samples /n
      samples = dst['samples'] = $1.to_i
      return soxi_failed(infile, 0) if samples == 0

      out =~ /^Channels\s*:\s*(\d+)/n and dst['channels'] = $1.to_i
      out =~ /^Sample Rate\s*:\s*(\d+)/n and dst['rate'] = $1.to_i
      out =~ /^Precision\s*:\s*(\d+)-bit/n and dst['bits'] = $1.to_i

      enc = Encoding.default_external # typically Encoding::UTF_8
      if out =~ /\nComments\s*:[ \t]*\n?(.*)\z/mn
        comments = dst['comments'] = {}
        key = nil
        $1.split(/\n/n).each do |line|
          if line.sub!(/^([^=]+)=/ni, '')
            key = DTAS.dedupe_str(DTAS.try_enc($1.upcase, enc))
          end
          (comments[key] ||= ''.b) << "#{line}\n" unless line.empty?
        end
        comments.each do |k,v|
          v.chomp!
          DTAS.try_enc(v, enc)
          comments[k] = DTAS.dedupe_str(v)
        end
      end
      dst
    end
  end

  def try(infile, offset = nil, trim = nil)
    ent = mcache_lookup(infile) or return
    ret = source_file_dup(infile, offset, trim)
    ret.instance_eval do
      @samples = ent['samples']
      @format = DTAS::Format.load(ent)
      @comments = ent['comments']
    end
    ret
  end

  def format
    @format ||= begin
      ent = mcache_lookup(@infile)
      ent ? DTAS::Format.load(ent) : nil
    end
  end

  def duration
    samples / format.rate.to_f
  end

  # This is the number of samples according to the samples in the source
  # file itself, not the decoded output
  def samples
    (@samples ||= begin
      ent = mcache_lookup(@infile)
      ent ? ent['samples'] : nil
     end) || 0
  end

  def __load_comments
    tmp = {}
    case @infile
    when String
      ent = mcache_lookup(@infile) and tmp = ent['comments']
    end
    tmp
  end

  def src_spawn(player_format, rg_state, opts)
    raise "BUG: #{self.inspect}#src_spawn called twice" if @to_io
    e = @env.merge!(player_format.to_env)
    e["INFILE"] = xs(@infile)

    # make sure these are visible to the "current" command...
    e["TRIMFX"] = trimfx
    e["RGFX"] = rg_state.effect(self) || nil
    e.merge!(@rg.to_env) if @rg

    @pid = dtas_spawn(e, command_string, opts)
  end

  def to_hsh
    to_hash.delete_if { |k,v| v == SOX_DEFAULTS[k] }
  end

  def source_defaults
    SOX_DEFAULTS
  end
end

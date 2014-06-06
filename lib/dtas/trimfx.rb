# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'parse_time'
require 'shellwords'

class DTAS::TrimFX
  include DTAS::ParseTime

  attr_reader :tbeg
  attr_reader :tlen
  attr_reader :cmd

  def initialize(args)
    args = args.dup
    case args.shift
    when "trim"
      parse_trim!(args)
    when "all"
      @tbeg = 0
      @tlen = nil
    else
      raise ArgumentError, "#{args.inspect} not understood"
    end
    case tmp =  args.shift
    when "sh" then @cmd = args
    when "sox" then tfx_sox(args)
    when "eca" then tfx_eca(args)
    when nil
      @cmd = []
    else
      raise ArgumentError, "unknown effect type: #{tmp}"
    end
  end

  def tfx_sox(args)
    @cmd = %w(sox $SOXIN $SOXOUT $TRIMFX)
    @cmd.concat(args)
    @cmd.concat(%w($FADEFX))
  end

  def tfx_eca(args)
    @cmd = %w(sox $SOXIN $SOX2ECA $TRIMFX)
    @cmd.concat(%w(| ecasound $ECAFMT -i stdin -o stdout))
    @cmd.concat(args)
    @cmd.concat(%w(| sox $ECA2SOX - $SOXOUT $FADEFX))
  end

  def to_sox_arg(format)
    if @tbeg && @tlen
      beg = @tbeg * format.rate
      len = @tlen * format.rate
      %W(trim #{beg.round}s #{len.round}s)
    elsif @tbeg
      return [] if @tbeg == 0
      beg = @tbeg * format.rate
      %W(trim #{beg.round}s)
    else
      []
    end
  end

  def parse_trim!(args)
    tbeg = parse_time(args.shift)
    if args[0] =~ /\A=?[\d\.]+\z/
      tlen = args.shift
      is_stop_time = tlen.sub!(/\A=/, "") ? true : false
      tlen = parse_time(tlen)
      if is_stop_time
        tlen = tlen - tbeg
      end
    else
      tlen = nil
    end
    @tbeg = tbeg
    @tlen = tlen
  end
end

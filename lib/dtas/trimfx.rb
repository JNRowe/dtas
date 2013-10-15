# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require 'shellwords'

class DTAS::TrimFX
  attr_reader :tbeg
  attr_reader :tlen

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

  def parse_time(tbeg)
    case tbeg
    when /\A\d+\z/
      tbeg.to_i
    when /\A[\d\.]+\z/
      tbeg.to_f
    when /\A[:\d\.]+\z/
      hhmmss = tbeg.dup
      rv = hhmmss.sub!(/\.(\d+)\z/, "") ? "0.#$1".to_f : 0

      # deal with HH:MM:SS
      t = hhmmss.split(/:/)
      raise ArgumentError, "Bad time format: #{hhmmss}" if t.size > 3

      mult = 1
      while part = t.pop
        rv += part.to_i * mult
        mult *= 60
      end
      rv
    else
      raise ArgumentError, "unparseable: #{tbeg.inspect}"
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

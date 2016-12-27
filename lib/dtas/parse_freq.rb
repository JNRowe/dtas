# Copyright (C) 2015-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'
module DTAS::ParseFreq # :nodoc:

  # may return a negative frequency meaning lowpass
  def parse_freq(val, round = true)
    case val
    when String
      val = val.dup
      mult = val.sub!(/k\z/, '') ? 1000 : 1
      val = (val.to_f * mult)
    when Numeric
      val
    else
      raise ArgumentError, "non-numeric value given"
    end

    case round
    when true, :int
      val.round
    when :float
      val.to_f
    else
      raise ArgumentError, "usage: parse_freq(val, (true|:round))"
    end
  end
end

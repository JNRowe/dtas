# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)

require_relative '../dtas'
module DTAS::ParseFreq

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

# frozen_string_literal: true
# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'

module DTAS::ParseTime # :nodoc:
  # convert a string time to seconds, returning a Floot or Integer
  def parse_time(time)
    case time
    when Numeric
      time
    when /\A\d+\z/
      time.to_i
    when /\A[\d\.]+\z/
      time.to_f
    when /\A[:\d\.]+\z/
      hhmmss = time.dup
      rv = hhmmss.sub!(/\.(\d+)\z/, "") ? "0.#$1".to_f : 0

      # deal with HH:MM:SS
      t = hhmmss.split(':')
      raise ArgumentError, "Bad time format: #{hhmmss}" if t.size > 3

      mult = 1
      while part = t.pop
        rv += part.to_i * mult
        mult *= 60
      end
      rv
    else
      raise ArgumentError, "unparseable: #{time.inspect}"
    end
  end
end

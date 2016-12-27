# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'

# embedded CUE sheet representation for -player
class DTAS::CueIndex # :nodoc:
  attr_reader :offset
  attr_reader :index

  def initialize(index, offset)
    @index = index.to_i

    # must be compatible with the sox "trim" effect
    @offset = offset # "#{INTEGER}s" (samples) or HH:MM:SS:FRAC
  end

  def to_hash
    { "index" => @index, "offset" => @offset }
  end

  def offset_samples(format)
    case @offset
    when /\A(\d+)s\z/
      $1.to_i
    else
      format.hhmmss_to_samples(@offset)
    end
  end

  def pregap?
    @index == 0
  end

  def track?
    @index == 1
  end

  def subindex?
    @index > 1
  end
end

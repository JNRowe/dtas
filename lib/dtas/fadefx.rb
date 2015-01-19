# Copyright (C) 2013-2015, all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'parse_time'

# --------- time --------->
# _____   _______   ______
#      \ /       \ /
# prev  X   cur   X   next
# _____/ \_______/ \______
#
# out_prev - controls the downward slope from prev
# in_cur   - controls the upward slope into cur
# out_cur  - controls the downward slope from cur
# in_next  - controls the upward slope into next
class DTAS::FadeFX # :nodoc:
  include DTAS::ParseTime

  attr_reader :out_prev, :in_cur, :out_cur, :in_next
  F = Struct.new(:type, :flen)

  def initialize(args)
    args =~ /\A([^,]*),([^,]*);([^,]*),([^,]*)\z/ or
      raise ArgumentError, "bad fade format"
    fades = [ $1, $2, $3, $4 ]
    %w(out_prev in_cur out_cur in_next).each do |iv|
      instance_variable_set("@#{iv}", parse!(fades.shift))
    end
  end

  # q - quarter of a sine wave
  # h - half a sine wave
  # t - linear (`triangular') slope
  # l - logarithmic
  # p - inverted parabola
  # default is 't' (sox defaults to 'l', but triangular makes more sense
  # when concatenating
  def parse!(str)
    return nil if str.empty?
    type = "t"
    str.sub!(/\A([a-z])/, "") and type = $1
    F.new(type, parse_time(str))
  end
end

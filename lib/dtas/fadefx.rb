# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'parse_time'

class DTAS::FadeFX
  include DTAS::ParseTime
  attr_reader :out_prev, :in_main, :out_main, :in_next
  F = Struct.new(:type, :len)

  def initialize(args)
    args =~ /\Afade=([^,]*),([^,]*);([^,]*),([^,]*)\z/ or
      raise ArgumentError, "bad fade format"
    fades = [ $1, $2, $3, $4 ]
    %w(out_prev in_main out_main in_next).each do |iv|
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
    type = "t"
    str.sub!(/\A([a-z])/, "") and type = $1
    F[type, parse_time(str)]
  end
end

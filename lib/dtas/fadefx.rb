# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'
require_relative 'parse_time'
require_relative 'xs'

# note: This is sox-specific
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
  include DTAS::XS

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

  def fade_cur_fx(format, tbeg, tlen, args = [])
    fx = %W(trim #{tbeg}s #{tlen}s)
    fx.concat(args)
    if @in_cur && @out_cur && @in_cur.type == @out_cur.type
      f = %W(fade #{@in_cur.type} #{@in_cur.flen} #{tlen}s #{@out_cur.flen})
      fx.concat(f)
    else # differing fade types for in/out, chain them:
      fpart = @in_cur and
        fx.concat(%W(fade #{fpart.type} #{fpart.flen} 0 0))
      fpart = @out_cur and
        fx.concat(%W(fade #{fpart.type} 0 #{tlen}s #{fpart.flen}))
    end
    fx
  end

  def fade_out_prev_fx(format, tbeg, tlen)
    fx = %W(trim #{tbeg}s)

    if fpart = @out_prev
      out_len = format.hhmmss_to_samples(fpart.flen)
      fx.concat(%W(fade #{fpart.type} 0 #{out_len}s #{out_len}s))
      remain = tlen - out_len

      # fade-out is longer than tlen, so truncate again:
      remain < 0 and fx.concat(%W(trim 0 #{tlen}s))

      # pad with silence, this is where fade_cur_fx goes
      remain > 0 and fx.concat(%W(pad #{remain}s@#{out_len}s))
    end
    fx
  end

  def fade_in_next_fx(format, tbeg, tlen)
    fpart = @in_next
    flen = fpart ? fpart.flen : 0
    nlen = format.hhmmss_to_samples(flen)
    nbeg = tbeg + tlen - nlen
    npad = nbeg - tbeg
    if npad < 0
      warn("in_next should not exceed range: #{inspect} @trim " \
           "#{tbeg}s #{tlen}s\nclamping to #{tbeg}")
      nbeg = tbeg
    end

    fx = %W(trim #{nbeg}s #{nlen}s)
    nlen != 0 and
      fx.concat(%W(fade #{fpart.type} #{nlen}s 0 0))

    # likely, the pad section is where fade_cur_fx goes
    npad > 0 and fx.concat(%W(pad #{npad}s@0s))
    fx
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
    str.sub!(/\A([a-z])/, "") and type = DTAS.dedupe_str($1)
    F.new(type, parse_time(str))
  end
end

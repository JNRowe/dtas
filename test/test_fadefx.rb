# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative 'helper'
require 'dtas/fadefx'
require 'dtas/format'

class TestFadeFX < Testcase
  def test_fadefx
    ffx = DTAS::FadeFX.new("t1,t3.1;l4,t1")
    assert_equal 't', ffx.out_prev.type
    assert_equal 1, ffx.out_prev.flen
    assert_equal 't', ffx.in_cur.type
    assert_equal 3.1, ffx.in_cur.flen
    assert_equal 'l', ffx.out_cur.type
    assert_equal 4, ffx.out_cur.flen
    assert_equal 't', ffx.in_next.type
    assert_equal 1, ffx.in_next.flen

    fmt = DTAS::Format.new
    fmt.rate = 48000
    tbeg = 0
    tlen = 48000 * 9

    # XXX: this isn't testing much...
    cur = ffx.fade_cur_fx(fmt, tbeg, tlen, %w(vol +3dB))
    assert_equal(%w(trim 0s 432000s vol +3dB
                    fade t 3.1 0 0 fade l 0 432000s 4), cur)
    out = ffx.fade_out_prev_fx(fmt, tbeg, tlen)
    assert_equal(%w(trim 0s
                    fade t 0 48000s 48000s pad 384000s@48000s), out)
    inn = ffx.fade_in_next_fx(fmt, tbeg, tlen)
    assert_equal(%w(trim 384000s 48000s
                    fade t 48000s 0 0 pad 384000s@0s), inn)
  end

  def test_fadefx_no_cur
    ffx = DTAS::FadeFX.new("t1,;,t1")
    assert_equal 't', ffx.out_prev.type
    assert_equal 1, ffx.out_prev.flen
    assert_nil ffx.in_cur
    assert_nil ffx.out_cur
    assert_equal 't', ffx.in_next.type
    assert_equal 1, ffx.in_next.flen
  end
end

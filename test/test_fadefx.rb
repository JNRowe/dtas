# Copyright (C) 2013-2015, all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative 'helper'
require 'dtas/fadefx'

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

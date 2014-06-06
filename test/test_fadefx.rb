# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative 'helper'
require 'dtas/fadefx'

class TestFadeFX < Testcase
  def test_fadefx
    ffx = DTAS::FadeFX.new("fade=t1,t3.1;l4,t1")
    assert_equal 't', ffx.out_prev.type
    assert_equal 1, ffx.out_prev.len
    assert_equal 't', ffx.in_main.type
    assert_equal 3.1, ffx.in_main.len
    assert_equal 'l', ffx.out_main.type
    assert_equal 4, ffx.out_main.len
    assert_equal 't', ffx.in_next.type
    assert_equal 1, ffx.in_next.len
  end
end

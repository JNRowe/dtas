# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/splitfx'

class TestSplitfx < Testcase
  def test_cdda
    sfx = DTAS::SplitFX.new
    sfx.instance_eval do
      @infmt = DTAS::Format.load("rate"=>44100)
    end
    assert_equal 118554000, sfx.t2s_cdda('44:48.3')
  end
end

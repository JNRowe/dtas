# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'dtas/rg_state'

class TestRGState < Testcase

  def test_rg_state
    rg = DTAS::RGState.new
    assert_equal({}, rg.to_hsh)
    rg.preamp = 0.1
    assert_equal({"preamp" => 0.1}, rg.to_hsh)
    rg.preamp = 0
    assert_equal({}, rg.to_hsh)
  end

  def test_load
    rg = DTAS::RGState.load("preamp" => 0.666)
    assert_equal({"preamp" => 0.666}, rg.to_hsh)
  end

  def test_rg_vol_norm
    rg = DTAS::RGState.new
    assert_nil rg.rg_vol_norm(0.999999999)
    assert_match(%r{\Again 0.827}, rg.rg_vol_norm(0.9))
  end

  def test_mode_set
    rg = DTAS::RGState.new
    orig = rg.mode
    assert_nil DTAS::RGState::RG_DEFAULT["mode"]
    assert_nil orig
    %w(album_gain track_gain album_peak track_peak).each do |t|
      rg.mode = t
      assert_equal t, rg.mode
    end
  end
end

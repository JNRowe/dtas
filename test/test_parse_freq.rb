# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require './test/helper'
require 'dtas/parse_freq'

class TestParseFreq < Testcase
  include DTAS::ParseFreq

  def test_parse_freq
    assert_equal(4000, parse_freq('4k'))
    assert_equal(-4000, parse_freq('-4k'))
    assert_equal(-4900, parse_freq('-4.9k'))
    assert_equal(-4900, parse_freq('-4.9k', :int))

    assert_equal(4900.5, parse_freq('4.9005k', :float))
  end
end

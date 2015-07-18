# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
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

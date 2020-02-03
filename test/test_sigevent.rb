# Copyright (C) 2019-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative 'helper'
require 'dtas'
require 'dtas/sigevent'

class TestSigevent < Testcase
  def test_sigevent
    io = DTAS::Sigevent.new
    io.signal
    assert IO.select([io]), 'IO.select returns'
    res = io.readable_iter do |f,arg|
      assert_same io, f
      assert_nil arg
    end
    assert_equal :wait_readable, res
    assert_nil io.close
  end
end

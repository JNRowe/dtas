# Copyright (C) 2016-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'dtas/mcache'

class TestMcache < Testcase
  def test_mcache
    mc = DTAS::Mcache.new
    exist = nil
    mc.lookup('hello') { |infile, hash| exist = hash }
    assert_kind_of Hash, exist
    assert_equal 'hello', exist[:infile]
    assert_operator exist[:btime], :<=, DTAS.now
    assert_same exist, mc.lookup('hello')
    assert_nil mc.lookup('HELLO')
    assert_same exist, mc.lookup('hello'), 'no change after miss'
  end
end

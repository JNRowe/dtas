# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'dtas/mcache'
require 'tempfile'

class TestMcache < Testcase
  def test_mcache
    tmp = Tempfile.new(%W(tmp .sox))
    fn = tmp.path
    cmd = %W(sox -r 44100 -b 16 -c 2 -n #{fn} trim 0 1)
    system(*cmd) or skip
    mc = DTAS::Mcache.new
    exist = nil
    mc.lookup(fn) { |infile, hash|
      hash[:ctime] = File.stat(infile).ctime
      exist = hash
    }
    assert_kind_of Hash, exist
    assert_equal fn, exist[:infile]
    assert_operator exist[:btime], :<=, DTAS.now
    assert_same exist, mc.lookup(fn)
    assert_nil mc.lookup('HELLO')
    assert_same exist, mc.lookup(fn), 'no change after miss'
  ensure
    tmp.close!
  end
end

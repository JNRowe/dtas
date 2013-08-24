# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'dtas/sink_reader_play'
require './test/helper'

class TestSinkReaderPlay < Minitest::Unit::TestCase
  FMT = "\rIn:%-5s %s [%s] Out:%-5s [%6s|%-6s] %s Clip:%-5s"
  ZERO = "\rIn:0.00% 00:00:00.00 [00:00:00.00] Out:0     " \
         "[      |      ]        Clip:0    "

  def setup
    @srp = DTAS::SinkReaderPlay.new
  end

  def teardown
    @srp.close
  end

  def test_sink_reader_play
    @srp.wr.write(ZERO)
    assert_equal :wait_readable, @srp.readable_iter
    assert_equal "0", @srp.clips
    assert_equal nil, @srp.headroom
    assert_equal "[      |      ]", @srp.meter
    assert_equal "0", @srp.out
    assert_equal "00:00:00.00", @srp.time

    noheadroom = sprintf(FMT, '0.00%', '00:00:37.34', '00:00:00.00',
                         '1.65M', ' -====', '====  ', ' ' * 6, '3M')
    @srp.wr.write(noheadroom)
    assert_equal :wait_readable, @srp.readable_iter
    assert_equal '3M', @srp.clips
    assert_equal nil, @srp.headroom
    assert_equal '[ -====|====  ]', @srp.meter
    assert_equal '1.65M', @srp.out
    assert_equal '00:00:37.34', @srp.time

    headroom = sprintf(FMT, '0.00%', '00:00:37.43', '00:00:00.00',
                         '1.66M', ' =====', '===== ', 'Hd:1.2', '3.1M')
    @srp.wr.write(headroom)
    assert_equal :wait_readable, @srp.readable_iter
    assert_equal '3.1M', @srp.clips
    assert_equal '1.2', @srp.headroom
    assert_equal '[ =====|===== ]', @srp.meter
    assert_equal '1.66M', @srp.out
    assert_equal '00:00:37.43', @srp.time
  end
end

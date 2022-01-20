# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'dtas/player'

class TestPlayerClientHandler < Testcase
  class MockIO < Array
    alias emit push
  end

  include DTAS::Player::ClientHandler

  def setup
    @sinks = {}
    @io = MockIO.new
    @srv = nil # unused mock
  end

  def test_delete
    @sinks["default"] = DTAS::Sink.new
    @targets = []
    dpc_sink(@io, %w(rm default))
    assert @sinks.empty?
    assert_equal %w(OK), @io.to_a
  end

  def test_delete_noexist
    dpc_sink(@io, %w(rm default))
    assert @sinks.empty?
    assert_equal ["ERR default not found"], @io.to_a
  end

  def test_env
    dpc_sink(@io, %w(ed default env.FOO=bar))
    assert_equal "bar", @sinks["default"].env["FOO"]
    dpc_sink(@io, %w(ed default env.FOO=))
    assert_equal "", @sinks["default"].env["FOO"]
    dpc_sink(@io, %w(ed default env#FOO))
    assert_nil @sinks["default"].env["FOO"]
  end

  def test_sink_ed
    command = 'sox -t $SOX_FILETYPE -r $RATE -c $CHANNELS - \
      -t s$SINK_BITS -r $SINK_RATE -c $SINK_CHANNELS - | \
    aplay -D hw:DAC_1 -v -q -M --buffer-size=500000 --period-size=500 \
      --disable-softvol --start-delay=100 \
      --disable-format --disable-resample --disable-channels \
      -t raw -c $SINK_CHANNELS -f S${SINK_BITS}_3LE -r $SINK_RATE
    '
    dpc_sink(@io, %W(ed foo command=#{command}))
    assert_equal command, @sinks["foo"].command
    assert_empty @sinks["foo"].env
    dpc_sink(@io, %W(ed foo env.SINK_BITS=24))
    dpc_sink(@io, %W(ed foo env.SINK_CHANNELS=2))
    dpc_sink(@io, %W(ed foo env.SINK_RATE=48000))
    expect = {
      "SINK_BITS" => "24",
      "SINK_CHANNELS" => "2",
      "SINK_RATE" => "48000",
    }
    assert_equal expect, @sinks["foo"].env
    @io.all? { |s| assert_equal "OK", s }
    assert_equal 4, @io.size
  end

  def test_cat
    sink = DTAS::Sink.new
    sink.name = "default"
    sink.command += "dither -s"
    @sinks["default"] = sink
    dpc_sink(@io, %W(cat default))
    assert_equal 1, @io.size
    hsh = DTAS.yaml_load(@io[0])
    assert_kind_of Hash, hsh
    assert_equal "default", hsh["name"]
    assert_match("dither -s", hsh["command"])
  end

  def test_ls
    expect = %w(a b c d)
    expect.each { |s| @sinks[s] = true }
    dpc_sink(@io, %W(ls))
    assert_equal expect, Shellwords.split(@io[0])
  end

  def test_env_dump
    dpc_env(@io, [])
    res = @io[0]
    result = {}
    Shellwords.split(res).each do |kv|
      k, v = kv.split('=', 2)
      result[k] = v
    end
    expect = ENV.to_hash
    assert_equal expect, result
  end
end

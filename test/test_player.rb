# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'tempfile'
require 'dtas/player'

class TestPlayer < Testcase
  def setup
    @player = nil
    tmp = Tempfile.new(%w(dtas-player-test .sock))
    @path = tmp.path
    File.unlink(@path)
  end

  def teardown
    @player.close if @player
  end

  def test_player_new
    player = DTAS::Player.new
    player.socket = @path
    player.bind
    assert File.socket?(@path)
  ensure
    player.close
    refute File.socket?(@path)
  end

  def test_player_serialize
    @player = DTAS::Player.new
    @player.socket = @path
    @player.bind
    hash = @player.to_hsh
    assert_equal({"socket" => @path}, hash)
  end

  def test_player_serialize_format
    fmt = DTAS::Format.new
    fmt.type = "f32"
    fmt.rate = 48000
    player = DTAS::Player.load("format" => fmt.to_hsh)
    fhash = player.to_hsh["format"]
    assert_equal "f32", fhash["type"]
    assert_equal 48000, fhash["rate"]
  end
end

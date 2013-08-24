# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'tempfile'
require 'dtas/player'

class TestPlayer < Minitest::Unit::TestCase
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
end

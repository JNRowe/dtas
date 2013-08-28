# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/sink'
require 'yaml'

class TestSink < Minitest::Unit::TestCase
  def test_serialize_reload
    sink = DTAS::Sink.new
    sink.name = "DAC"
    hash = sink.to_hsh
    assert_kind_of Hash, hash
    refute_match(%r{ruby}i, hash.to_yaml, "ruby guts exposed: #{hash}")

    s2 = DTAS::Sink.load(hash)
    assert_equal sink.to_hsh, s2.to_hsh
    assert_equal hash, s2.to_hsh
  end

  def test_name
    sink = DTAS::Sink.new
    sink.name = "dac1"
    assert_equal({"name" => "dac1"}, sink.to_hsh)
  end

  def test_inactive_load
    orig = { "active" => false }.freeze
    tmp = orig.to_yaml
    assert_equal orig, YAML.load(tmp)
  end
end

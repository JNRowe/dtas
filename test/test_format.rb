# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'tempfile'
require 'dtas/format'

class TestFormat < Testcase
  def test_initialize
    fmt = DTAS::Format.new
    assert_equal %w(-ts32 -c2 -r44100), fmt.to_sox_arg
    hash = fmt.to_hsh
    assert_equal({}, hash)
  end

  def test_equal
    fmt = DTAS::Format.new
    assert_equal fmt, fmt.dup
  end

  def test_nonstandard
    fmt = DTAS::Format.new
    fmt.type = "s16"
    fmt.rate = 48000
    fmt.channels = 4
    hash = fmt.to_hsh
    assert_kind_of Hash, hash
    assert_equal %w(channels rate type), hash.keys.sort
    assert_equal "s16", hash["type"]
    assert_equal 48000, hash["rate"]
    assert_equal 4, hash["channels"]

    # back to stereo
    fmt.channels = 2
    hash = fmt.to_hsh
    assert_equal %w(rate type), hash.keys.sort
    assert_equal "s16", hash["type"]
    assert_equal 48000, hash["rate"]
    assert_nil hash["channels"]
  end

  def test_bytes_per_sample
    fmt = DTAS::Format.new
    assert_equal 4, fmt.bytes_per_sample
    fmt.type = "f64"
    assert_equal 8, fmt.bytes_per_sample
    fmt.type = "f32"
    assert_equal 4, fmt.bytes_per_sample
    fmt.type = "s16"
    assert_equal 2, fmt.bytes_per_sample
  end

  def test_valid_type
    fmt = DTAS::Format.new
    %w(s16 s24 s32 f32 f64).each do |t|
      assert fmt.valid_type?(t)
    end
    %w(flac wav wtf).each do |t|
      refute fmt.valid_type?(t)
    end
  end
end

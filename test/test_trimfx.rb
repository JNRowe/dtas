# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/trimfx'
require 'dtas/format'
require 'yaml'

class TestTrimFX < Testcase
  def test_example
    ex = YAML.load(File.read("examples/trimfx.sample.yml"))
    effects = []
    ex["effects"].each do |line|
      words = Shellwords.split(line)
      case words[0]
      when "trim"
        tfx = DTAS::TrimFX.new(words)
        assert_equal 52.0, tfx.tbeg
        assert_equal 1.0, tfx.tlen
        effects << tfx
      end
    end
    assert_equal 4, effects.size
  end

  def test_all
    tfx = DTAS::TrimFX.new(%w(all))
    assert_equal 0, tfx.tbeg
    assert_nil tfx.tlen
    assert_equal [], tfx.to_sox_arg(DTAS::Format.new)
  end

  def test_time
    tfx = DTAS::TrimFX.new(%w(trim 2:30 3.1))
    assert_equal 150, tfx.tbeg
    assert_equal 3.1, tfx.tlen
  end

  def test_to_sox_arg
    tfx = DTAS::TrimFX.new(%w(trim 1 0.5))
    assert_equal %w(trim 44100s 22050s), tfx.to_sox_arg(DTAS::Format.new)

    tfx = DTAS::TrimFX.new(%w(trim 1 sox vol -1dB))
    assert_equal %w(trim 44100s), tfx.to_sox_arg(DTAS::Format.new)
  end

  def test_tfx_effects
    tfx = DTAS::TrimFX.new(%w(trim 1 sox vol -1dB))
    assert_equal %w(sox $SOXIN $SOXOUT $TRIMFX vol -1dB $FADEFX), tfx.cmd
  end
end

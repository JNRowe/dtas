# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/trimfx'
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
  end

  def test_time
    tfx = DTAS::TrimFX.new(%w(trim 2:30 3.1))
    assert_equal 150, tfx.tbeg
    assert_equal 3.1, tfx.tlen
  end
end

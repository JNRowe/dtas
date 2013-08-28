# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/source/av'
require 'tempfile'

class TestSourceAv < Minitest::Unit::TestCase
  def teardown
    @tempfiles.each { |tmp| tmp.close! }
  end

  def setup
    @tempfiles = []
  end

  def x(cmd)
    system(*cmd)
    assert $?.success?, cmd.inspect
  end

  def new_file(suffix)
    tmp = Tempfile.new(%W(tmp .#{suffix}))
    @tempfiles << tmp
    cmd = %W(sox -r 44100 -b 16 -c 2 -n #{tmp.path} trim 0 1)
    return tmp if system(*cmd)
    nil
  end

  def test_flac
    return if `which metaflac`.strip.size == 0
    tmp = new_file('flac') or return

    x(%W(metaflac --set-tag=FOO=BAR #{tmp.path}))
    x(%W(metaflac --add-replay-gain #{tmp.path}))
    source = DTAS::Source::Av.new.try(tmp.path)
    assert_equal source.comments["FOO"], "BAR", source.inspect
    rg = source.replaygain
    assert_kind_of DTAS::ReplayGain, rg
    assert_in_delta 0.0, rg.track_peak.to_f, 0.00000001
    assert_in_delta 0.0, rg.album_peak.to_f, 0.00000001
    assert_operator rg.album_gain.to_f, :>, 1
    assert_operator rg.track_gain.to_f, :>, 1
  end

  def test_mp3gain
    return if `which mp3gain`.strip.size == 0
    a = new_file('mp3') or return
    b = new_file('mp3') or return

    # redirect stdout to /dev/null temporarily, mp3gain is noisy
    File.open("/dev/null", "w") do |null|
      old_out = $stdout.dup
      $stdout.reopen(null)
      begin
        x(%W(mp3gain -q #{a.path} #{b.path}))
      ensure
        $stdout.reopen(old_out)
        old_out.close
      end
    end

    source = DTAS::Source::Av.new.try(a.path)
    rg = source.replaygain
    assert_kind_of DTAS::ReplayGain, rg
    assert_in_delta 0.0, rg.track_peak.to_f, 0.00000001
    assert_in_delta 0.0, rg.album_peak.to_f, 0.00000001
    assert_operator rg.album_gain.to_f, :>, 1
    assert_operator rg.track_gain.to_f, :>, 1
  end

  def test_offset
    tmp = new_file('flac') or return
    source = DTAS::Source::Av.new.try(*%W(#{tmp.path} 5s))
    assert_equal 5, source.offset_samples

    source = DTAS::Source::Av.new.try(*%W(#{tmp.path} 1:00:00.5))
    expect = 1 * 60 * 60 * 44100 + (44100/2)
    assert_equal expect, source.offset_samples

    source = DTAS::Source::Av.new.try(*%W(#{tmp.path} 1:10.5))
    expect = 1 * 60 * 44100 + (10 * 44100) + (44100/2)
    assert_equal expect, source.offset_samples

    source = DTAS::Source::Av.new.try(*%W(#{tmp.path} 10.03))
    expect = (10 * 44100) + (44100 * 3/100.0)
    assert_equal expect, source.offset_samples
  end

  def test_offset_us
    tmp = new_file('flac') or return
    source = DTAS::Source::Av.new.try(*%W(#{tmp.path} 441s))
    assert_equal 10000.0, source.offset_us

    source = DTAS::Source::Av.new.try(*%W(#{tmp.path} 22050s))
    assert_equal 500000.0, source.offset_us

    source = DTAS::Source::Av.new.try(tmp.path, '1')
    assert_equal 1000000.0, source.offset_us
  end
end unless `which avconv 2>/dev/null` =~ /avconv/ &&
           `which avprobe 2>/dev/null` =~ /avprobe/

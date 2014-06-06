# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/source/sox'
require 'tempfile'

class TestSource < Testcase
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

    source = DTAS::Source::Sox.new.try(tmp.path)
    x(%W(metaflac --set-tag=FOO=BAR #{tmp.path}))
    x(%W(metaflac --add-replay-gain #{tmp.path}))
    assert_equal source.comments["FOO"], "BAR"
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

    source = DTAS::Source::Sox.new.try(a.path)

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

    rg = source.replaygain
    assert_kind_of DTAS::ReplayGain, rg
    assert_in_delta 0.0, rg.track_peak.to_f, 0.00000001
    assert_in_delta 0.0, rg.album_peak.to_f, 0.00000001
    assert_operator rg.album_gain.to_f, :>, 1
    assert_operator rg.track_gain.to_f, :>, 1
  end

  def test_offset
    tmp = new_file('sox') or return
    source = DTAS::Source::Sox.new.try(*%W(#{tmp.path} 5s))
    assert_equal 5, source.offset_samples

    source = DTAS::Source::Sox.new.try(*%W(#{tmp.path} 1:00:00.5))
    expect = 1 * 60 * 60 * 44100 + (44100/2)
    assert_equal expect, source.offset_samples

    source = DTAS::Source::Sox.new.try(*%W(#{tmp.path} 1:10.5))
    expect = 1 * 60 * 44100 + (10 * 44100) + (44100/2)
    assert_equal expect, source.offset_samples

    source = DTAS::Source::Sox.new.try(*%W(#{tmp.path} 10.03))
    expect = (10 * 44100) + (44100 * 3/100.0)
    assert_equal expect, source.offset_samples
  end

  def test_offset_us
    tmp = new_file('sox') or return
    source = DTAS::Source::Sox.new.try(*%W(#{tmp.path} 441s))
    assert_equal 10000.0, source.offset_us

    source = DTAS::Source::Sox.new.try(*%W(#{tmp.path} 22050s))
    assert_equal 500000.0, source.offset_us

    source = DTAS::Source::Sox.new.try(tmp.path, '1')
    assert_equal 1000000.0, source.offset_us
  end

  def test_format_from_file
    Tempfile.open(%w(tmp .wav)) do |tmp|
      # generate an empty file with 1s of audio
      cmd = %W(sox -r 96000 -b 24 -c 2 -n #{tmp.path} trim 0 1)
      system(*cmd)
      assert $?.success?, "#{cmd.inspect} failed: #$?"
      fmt = DTAS::Source::Sox.new.try(tmp.path).format
      assert_equal 96000, fmt.rate
      assert_equal 2, fmt.channels
      tmp.unlink
    end
  end

  def test_flac_cuesheet_cdda
    return if `which metaflac`.strip.size == 0
    tmp = Tempfile.new(%W(tmp .flac))
    x(%W(sox -n -r44100 -b16 -c2 #{tmp.path} synth 5 pluck vol -1dB))
    cue = Tempfile.new(%W(tmp .cue))
    cue.puts %Q(FILE "ignored.flac" FLAC)
    cue.puts "  TRACK 01 AUDIO"
    cue.puts "    INDEX 01 00:00:00"
    cue.puts "  TRACK 02 AUDIO"
    cue.puts "    INDEX 01 00:01:40"
    cue.puts "  TRACK 03 AUDIO"
    cue.puts "    INDEX 01 00:03:00"
    cue.flush
    x(%W(metaflac --import-cuesheet-from=#{cue.path} #{tmp.path}))
    source = DTAS::Source::Sox.new.try(tmp.path)
    offsets = source.cuebreakpoints.map(&:offset)
    assert_equal %w(00:00 00:01.0.533333 00:03), offsets
    source.cuebreakpoints.all?(&:track?)
  end

  def test_flac_cuesheet_48
    return if `which metaflac`.strip.size == 0
    ver = `flac --version`.split(/ /)[1].strip
    ver.to_f >= 1.3 or return # flac 1.3.0 fixed non-44.1k rate support

    tmp = Tempfile.new(%W(tmp .flac))
    x(%W(sox -n -r48000 -c2 -b24 #{tmp.path} synth 5 pluck vol -1dB))
    cue = Tempfile.new(%W(tmp .cue))
    cue.puts %Q(FILE "ignored.flac" FLAC)
    cue.puts "  TRACK 01 AUDIO"
    cue.puts "    INDEX 01 00:00:00"
    cue.puts "  TRACK 02 AUDIO"
    cue.puts "    INDEX 01 00:01:00"
    cue.puts "  TRACK 03 AUDIO"
    cue.puts "    INDEX 01 00:03:00"
    cue.flush
    x(%W(metaflac --import-cuesheet-from=#{cue.path} #{tmp.path}))
    source = DTAS::Source::Sox.new.try(tmp.path)
    offsets = source.cuebreakpoints.map(&:offset)
    assert_equal %w(0s 48000s 144000s), offsets
    source.cuebreakpoints.all?(&:track?)
  end
end

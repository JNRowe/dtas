# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/player_integration'
class TestRgIntegration < Minitest::Unit::TestCase
  include PlayerIntegration

  def tmp_pluck(len = 5)
    pluck = Tempfile.open(%w(pluck .flac))
    cmd = %W(sox -R -n -r44100 -c2 -C0 #{pluck.path} synth #{len} pluck)
    assert system(*cmd), cmd
    cmd = %W(metaflac
             --set-tag=REPLAYGAIN_TRACK_GAIN=-2
             --set-tag=REPLAYGAIN_ALBUM_GAIN=-3.0
             --set-tag=REPLAYGAIN_TRACK_PEAK=0.666
             --set-tag=REPLAYGAIN_ALBUM_PEAK=0.999
             #{pluck.path})
    assert system(*cmd), cmd
    [ pluck, len ]
  end

  def test_rg_changes_added
    s = client_socket
    pluck, len = tmp_pluck

    # create the default sink, as well as a dumper
    dumper = Tempfile.open(%w(dump .sox))
    dump_pid = Tempfile.new(%w(dump .pid))
    default_pid = default_sink_pid(s)
    dump_cmd = "echo $$ > #{dump_pid.path}; sox $SOXFMT - #{dumper.path}"
    s.send("sink ed dump active=true command='#{dump_cmd}'", Socket::MSG_EOR)
    assert_equal("OK", s.readpartial(666))

    # start playback!
    s.send("enq \"#{pluck.path}\"", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)

    # wait for playback to start
    yaml = cur = nil
    Timeout.timeout(5) do
      begin
        s.send("current", Socket::MSG_EOR)
        cur = YAML.load(yaml = s.readpartial(1666))
      end while cur["current_offset"] == 0 && sleep(0.01)
    end

    assert_nil cur["current"]["env"]["RGFX"]

    assert_equal DTAS::Format.new.rate * len, cur["current_expect"]

    wait_files_not_empty(dump_pid)
    pid = read_pid_file(dump_pid)

    check_gain = proc do |expect, mode|
      s.send("rg mode=#{mode}", Socket::MSG_EOR)
      assert_equal "OK", s.readpartial(666)
      Timeout.timeout(5) do
        begin
          s.send("current", Socket::MSG_EOR)
          cur = YAML.load(yaml = s.readpartial(3666))
        end while cur["current"]["env"]["RGFX"] !~ expect && sleep(0.01)
      end
      assert_match expect, cur["current"]["env"]["RGFX"]
    end

    check_gain.call(%r{vol -3dB}, "album_gain")
    check_gain.call(%r{vol -2dB}, "track_gain")
    check_gain.call(%r{vol 1\.3}, "track_peak")
    check_gain.call(%r{vol 1\.0}, "album_peak")

    s.send("rg preamp+=1", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    s.send("rg", Socket::MSG_EOR)
    rg = YAML.load(yaml = s.readpartial(3666))
    assert_equal 1, rg["preamp"]

    s.send("rg preamp-=1", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    s.send("rg", Socket::MSG_EOR)
    rg = YAML.load(yaml = s.readpartial(3666))
    assert_nil rg["preamp"]

    s.send("rg preamp=2", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    s.send("rg", Socket::MSG_EOR)
    rg = YAML.load(yaml = s.readpartial(3666))
    assert_equal 2, rg["preamp"]

    s.send("rg preamp-=0.3", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    s.send("rg", Socket::MSG_EOR)
    rg = YAML.load(yaml = s.readpartial(3666))
    assert_equal 1.7, rg["preamp"]

    s.send("rg preamp-=-0.3", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    s.send("rg", Socket::MSG_EOR)
    rg = YAML.load(yaml = s.readpartial(3666))
    assert_equal 2.0, rg["preamp"]

    s.send("rg preamp-=+0.3", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    s.send("rg", Socket::MSG_EOR)
    rg = YAML.load(yaml = s.readpartial(3666))
    assert_equal 1.7, rg["preamp"]

    dethrottle_decoder(s)

    # ensure we did not change audio length
    wait_pid_dead(pid, len)
    samples = `soxi -s #{dumper.path}`.to_i
    assert_equal cur["current_expect"], samples
    assert_equal `soxi -d #{dumper.path}`, `soxi -d #{pluck.path}`

    stop_playback(default_pid, s)
  end
end

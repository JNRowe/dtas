# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/player_integration'
require 'dtas/util'
class TestRgIntegration < Testcase
  include PlayerIntegration
  include DTAS::Util

  def tmp_pluck(len = 5)
    pluck = Tempfile.open(%w(pluck .flac))
    cmd = %W(sox -R -n -r44100 -c2 -C0 #{pluck.path} synth #{len} pluck)
    assert system(*cmd), cmd.inspect
    cmd = %W(metaflac
             --set-tag=REPLAYGAIN_TRACK_GAIN=-2
             --set-tag=REPLAYGAIN_ALBUM_GAIN=-3.0
             --set-tag=REPLAYGAIN_TRACK_PEAK=0.666
             --set-tag=REPLAYGAIN_ALBUM_PEAK=0.999
             #{pluck.path})
    assert system(*cmd), cmd.inspect
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
    s.req_ok("sink ed dump active=true command='#{dump_cmd}'")

    # start playback!
    s.req_ok("enq \"#{pluck.path}\"")

    # wait for playback to start
    yaml = cur = nil
    Timeout.timeout(5) do
      begin
        cur = DTAS.yaml_load(yaml = s.req("current"))
      end while cur["current_offset"] == 0 && sleep(0.01)
    end

    assert_nil cur["current"]["env"]["RGFX"]

    assert_equal DTAS::Format.new.rate * len, cur["current_expect"]

    wait_files_not_empty(dump_pid)
    pid = read_pid_file(dump_pid)

    check_gain = proc do |expect, mode|
      s.req_ok("rg mode=#{mode}")
      Timeout.timeout(5) do
        begin
          yaml = s.req("current")
          cur = DTAS.yaml_load(yaml)
        end while cur["current"]["env"]["RGFX"] !~ expect && sleep(0.01)
      end
      assert_match expect, cur["current"]["env"]["RGFX"]
    end

    check_gain.call(%r{gain -3}, "album_gain")
    check_gain.call(%r{gain -2}, "track_gain")
    check_gain.call(%r{gain 0\.}, "album_peak")
    check_gain.call(%r{gain 2\.5}, "track_peak")

    s.req_ok("rg preamp+=1")
    rg = DTAS.yaml_load(yaml = s.req("rg"))
    assert_equal 1, rg["preamp"]

    s.req_ok("rg preamp-=1")
    rg = DTAS.yaml_load(yaml = s.req("rg"))
    assert_nil rg["preamp"]

    s.req_ok("rg preamp=2")
    rg = DTAS.yaml_load(yaml = s.req("rg"))
    assert_equal 2, rg["preamp"]

    s.req_ok("rg preamp-=0.3")
    rg = DTAS.yaml_load(yaml = s.req("rg"))
    assert_equal 1.7, rg["preamp"]

    s.req_ok("rg preamp-=-0.3")
    rg = DTAS.yaml_load(yaml = s.req("rg"))
    assert_equal 2.0, rg["preamp"]

    s.req_ok("rg preamp-=+0.3")
    rg = DTAS.yaml_load(yaml = s.req("rg"))
    assert_equal 1.7, rg["preamp"]

    dethrottle_decoder(s)

    # ensure we did not change audio length
    wait_pid_dead(pid, len)
    samples = `soxi -s #{dumper.path}`.to_i
    assert_equal cur["current_expect"], samples
    assert_equal `soxi -d #{dumper.path}`, `soxi -d #{pluck.path}`

    stop_playback(default_pid, s)
  end

  def test_rg_env_in_source
    s = client_socket
    s.req_ok("rg mode=album_gain")
    pluck, _ = tmp_pluck
    cmd = DTAS::Source::Sox::SOX_DEFAULTS["command"]
    fifo = tmpfifo
    s.req_ok("source ed sox command='env > #{fifo}; #{cmd}'")
    s.req_ok("sink ed default command='cat >/dev/null' active=true")
    s.req_ok(%W(enq #{pluck.path}))

    rg = {}
    File.readlines(fifo).each do |line|
      line =~ /\AREPLAYGAIN_/ or next
      k, v = line.chomp!.split(/=/)
      rg[k] = v
    end
    expect = {
      "REPLAYGAIN_TRACK_GAIN" => "-2",
      "REPLAYGAIN_ALBUM_GAIN" => "-3.0",
      "REPLAYGAIN_TRACK_PEAK" => "0.666",
      "REPLAYGAIN_ALBUM_PEAK" => "0.999",
    }
    assert_equal expect, rg
  end
end

# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/player_integration'
class TestPlayerIntegration < Minitest::Unit::TestCase
  include PlayerIntegration

  def test_cmd_rate
    pid = fork do
      @fmt.to_env.each { |k,v| ENV[k] = v }
      exec("sox -n $SOXFMT - synth 3 pinknoise | #@cmd")
    end
    t = Time.now
    _, _ = Process.waitpid2(pid)
    elapsed = Time.now - t
    assert_in_delta 3.0, elapsed, 0.5
  end if ENV["MATH_IS_HARD"] # ensure our @cmd timing is accurate

  def test_sink_close_after_play
    s = client_socket
    @cmd = "cat >/dev/null"
    default_pid = default_sink_pid(s)
    Tempfile.open('junk') do |junk|
      pink = "sox -n $SOXFMT - synth 0.0001 pinknoise | tee -i #{junk.path}"
      s.send("enq-cmd \"#{pink}\"", Socket::MSG_EOR)
      wait_files_not_empty(junk)
      assert_equal "OK", s.readpartial(666)
    end
    wait_files_not_empty(default_pid)
    pid = read_pid_file(default_pid)
    wait_pid_dead(pid)
  end

  def test_sink_killed_during_play
    s = client_socket
    default_pid = default_sink_pid(s)
    cmd = Tempfile.new(%w(sox-cmd .pid))
    pink = "echo $$ > #{cmd.path}; sox -n $SOXFMT - synth 100 pinknoise"
    s.send("enq-cmd \"#{pink}\"", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    wait_files_not_empty(cmd, default_pid)
    pid = read_pid_file(default_pid)
    Process.kill(:KILL, pid)
    cmd_pid = read_pid_file(cmd)
    wait_pid_dead(cmd_pid)
  end

  def test_sink_activate
    s = client_socket
    s.send("sink ls", Socket::MSG_EOR)
    assert_equal "default", s.readpartial(666)

    # setup two outputs

    # make the default sink trickle
    default_pid = Tempfile.new(%w(dtas-test .pid))
    pf = "echo $$ >> #{default_pid.path}; "
    s.send("sink ed default command='#{pf}#@cmd'", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)

    # make a sleepy sink trickle, too
    sleepy_pid = Tempfile.new(%w(dtas-test .pid))
    pf = "echo $$ >> #{sleepy_pid.path};"
    s.send("sink ed sleepy command='#{pf}#@cmd' active=true", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)

    # ensure both sinks were created
    s.send("sink ls", Socket::MSG_EOR)
    assert_equal "default sleepy", s.readpartial(666)

    # generate pinknoise
    pinknoise = "sox -n -r 44100 -c 2 -t s32 - synth 0 pinknoise"
    s.send("enq-cmd \"#{pinknoise}\"", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)

    # wait for sinks to start
    wait_files_not_empty(sleepy_pid, default_pid)

    # deactivate sleepy sink and ensure it's gone
    sleepy = File.read(sleepy_pid).to_i
    assert_operator sleepy, :>, 0
    Process.kill(0, sleepy)
    s.send("sink ed sleepy active=false", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)
    wait_pid_dead(sleepy)

    # ensure default sink is still alive
    default = File.read(default_pid).to_i
    assert_operator default, :>, 0
    Process.kill(0, default)

    # restart sleepy sink
    sleepy_pid.sync = true
    sleepy_pid.seek(0)
    sleepy_pid.truncate(0)
    s.send("sink ed sleepy active=true", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)

    # wait for sleepy sink
    wait_files_not_empty(sleepy_pid)

    # check sleepy restarted
    sleepy = File.read(sleepy_pid).to_i
    assert_operator sleepy, :>, 0
    Process.kill(0, sleepy)

    # stop playing current track
    s.send("skip", Socket::MSG_EOR)
    assert_equal "OK", s.readpartial(666)

    wait_pid_dead(sleepy)
    wait_pid_dead(default)
  end

  def test_env_change
    s = client_socket
    tmp = Tempfile.new(%w(env .txt))
    s.preq("sink ed default active=true command='cat >/dev/null'")
    assert_equal "OK", s.readpartial(666)

    s.preq("env FOO=BAR")
    assert_equal "OK", s.readpartial(666)
    s.preq(["enq-cmd", "echo $FOO | tee #{tmp.path}"])
    assert_equal "OK", s.readpartial(666)
    wait_files_not_empty(tmp)
    assert_equal "BAR\n", tmp.read

    tmp.rewind
    tmp.truncate(0)
    s.preq("env FOO#")
    assert_equal "OK", s.readpartial(666)
    s.preq(["enq-cmd", "echo -$FOO- | tee #{tmp.path}"])
    assert_equal "OK", s.readpartial(666)
    wait_files_not_empty(tmp)
    assert_equal "--\n", tmp.read
  end

  def test_sink_env
    s = client_socket
    tmp = Tempfile.new(%w(env .txt))
    s.preq("sink ed default active=true command='echo -$FOO- > #{tmp.path}'")
    assert_equal "OK", s.readpartial(666)

    s.preq("sink ed default env.FOO=BAR")
    assert_equal "OK", s.readpartial(666)
    s.preq(["enq-cmd", "echo HI"])
    assert_equal "OK", s.readpartial(666)
    wait_files_not_empty(tmp)
    assert_equal "-BAR-\n", tmp.read

    tmp.rewind
    tmp.truncate(0)
    s.preq("sink ed default env#FOO")
    assert_equal "OK", s.readpartial(666)

    Timeout.timeout(5) do
      begin
        s.preq("current")
        yaml = s.readpartial(66666)
        cur = YAML.load(yaml)
      end while cur["sinks"] && sleep(0.01)
    end

    s.preq(["enq-cmd", "echo HI"])
    assert_equal "OK", s.readpartial(666)
    wait_files_not_empty(tmp)
    assert_equal "--\n", tmp.read
  end

  def test_enq_head
    s = client_socket
    default_sink_pid(s)
    dump = Tempfile.new(%W(d .sox))
    s.preq "sink ed dump active=true command='sox $SOXFMT - #{dump.path}'"
    assert_equal "OK", s.readpartial(666)
    noise, len = tmp_noise
    s.preq("enq-head #{noise.path}")
    assert_equal "OK", s.readpartial(666)
    s.preq("enq-head #{noise.path} 4")
    assert_equal "OK", s.readpartial(666)
    s.preq("enq-head #{noise.path} 3")
    assert_equal "OK", s.readpartial(666)
    dethrottle_decoder(s)
    expect = Tempfile.new(%W(expect .sox))

    c = "sox #{noise.path} -t sox '|sox #{noise.path} -p trim 3' " \
            "-t sox '|sox #{noise.path} -p trim 4' #{expect.path}"
    assert system(c)
    Timeout.timeout(len) do
      begin
        s.preq("current")
        yaml = s.readpartial(66666)
        cur = YAML.load(yaml)
      end while cur["sinks"] && sleep(0.01)
    end
    assert(system("cmp", dump.path, expect.path),
           "files don't match #{dump.path} != #{expect.path}")
  end
end

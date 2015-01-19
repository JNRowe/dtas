# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/player_integration'
class TestPlayerIntegration < Testcase
  include PlayerIntegration
  include DTAS::SpawnFix

  def test_cmd_rate
    env = ENV.to_hash.merge(@fmt.to_env)
    cmd = "sox -n $SOXFMT - synth 3 pinknoise | #@cmd"
    pid = spawn(env, cmd)
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
      s.req_ok("enq-cmd \"#{pink}\"")
      wait_files_not_empty(junk)
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
    s.req_ok("enq-cmd \"#{pink}\"")
    wait_files_not_empty(cmd, default_pid)
    pid = read_pid_file(default_pid)
    Process.kill(:KILL, pid)
    cmd_pid = read_pid_file(cmd)
    wait_pid_dead(cmd_pid)
  end

  def test_sink_activate
    s = client_socket
    res = s.req("sink ls")
    assert_equal "default", res

    # setup two outputs

    # make the default sink trickle
    default_pid = Tempfile.new(%w(dtas-test .pid))
    pf = "echo $$ >> #{default_pid.path}; "
    s.req_ok("sink ed default command='#{pf}#@cmd'")

    # make a sleepy sink trickle, too
    sleepy_pid = Tempfile.new(%w(dtas-test .pid))
    pf = "echo $$ >> #{sleepy_pid.path};"
    s.req_ok("sink ed sleepy command='#{pf}#@cmd' active=true")

    # ensure both sinks were created
    res = s.req("sink ls")
    assert_equal "default sleepy", res

    # generate pinknoise
    pinknoise = "sox -n -r 44100 -c 2 -t s32 - synth 0 pinknoise"
    s.req_ok("enq-cmd \"#{pinknoise}\"")

    # wait for sinks to start
    wait_files_not_empty(sleepy_pid, default_pid)

    # deactivate sleepy sink and ensure it's gone
    sleepy = File.read(sleepy_pid).to_i
    assert_operator sleepy, :>, 0
    Process.kill(0, sleepy)
    s.req_ok("sink ed sleepy active=false")
    wait_pid_dead(sleepy)

    # ensure default sink is still alive
    default = File.read(default_pid).to_i
    assert_operator default, :>, 0
    Process.kill(0, default)

    # restart sleepy sink
    sleepy_pid.sync = true
    sleepy_pid.seek(0)
    sleepy_pid.truncate(0)
    s.req_ok("sink ed sleepy active=true")

    # wait for sleepy sink
    wait_files_not_empty(sleepy_pid)

    # check sleepy restarted
    sleepy = File.read(sleepy_pid).to_i
    assert_operator sleepy, :>, 0
    Process.kill(0, sleepy)

    # stop playing current track
    s.req_ok("skip")

    wait_pid_dead(sleepy)
    wait_pid_dead(default)
  end

  def test_env_change
    s = client_socket
    tmp = Tempfile.new(%w(env .txt))
    s.req_ok("sink ed default active=true command='cat >/dev/null'")

    s.req_ok("env FOO=BAR")
    s.req_ok(["enq-cmd", "echo $FOO | tee #{tmp.path}"])
    wait_files_not_empty(tmp)
    assert_equal "BAR\n", tmp.read

    tmp.rewind
    tmp.truncate(0)
    s.req_ok("env FOO#")
    s.req_ok(["enq-cmd", "echo -$FOO- | tee #{tmp.path}"])
    wait_files_not_empty(tmp)
    assert_equal "--\n", tmp.read
  end

  def test_sink_env
    s = client_socket
    tmp = Tempfile.new(%w(env .txt))
    s.req_ok("sink ed default active=true " \
             "command='echo -$FOO- > #{tmp.path}; cat >/dev/null'")

    s.req_ok("sink ed default env.FOO=BAR")
    s.req_ok(["enq-cmd", "echo HI"])
    wait_files_not_empty(tmp)
    assert_equal "-BAR-\n", tmp.read

    tmp.rewind
    tmp.truncate(0)
    s.req_ok("sink ed default env#FOO")

    Timeout.timeout(5) do
      begin
        yaml = s.req("current")
        cur = YAML.load(yaml)
      end while cur["sinks"] && sleep(0.01)
    end

    s.req_ok(["enq-cmd", "echo HI"])
    wait_files_not_empty(tmp)
    assert_equal "--\n", tmp.read
  end

  def test_enq_head
    s = client_socket
    default_sink_pid(s)
    dump = Tempfile.new(%W(d .sox))
    s.req_ok "sink ed dump active=true command='sox $SOXFMT - #{dump.path}'"
    noise, len = tmp_noise
    s.req_ok("enq-head #{noise.path}")
    s.req_ok("enq-head #{noise.path} 4")
    s.req_ok("enq-head #{noise.path} 3")
    dethrottle_decoder(s)
    expect = Tempfile.new(%W(expect .sox))

    c = "sox #{noise.path} -t sox '|sox #{noise.path} -p trim 3' " \
            "-t sox '|sox #{noise.path} -p trim 4' #{expect.path}"
    assert system(c)
    Timeout.timeout(len) do
      begin
        yaml = s.req("current")
        cur = YAML.load(yaml)
      end while cur["sinks"] && sleep(0.01)
    end
    assert(system("cmp", dump.path, expect.path),
           "files don't match #{dump.path} != #{expect.path}")
  end

  def test_cd_pwd
    s = client_socket
    pwd = Dir.pwd

    assert_equal pwd, s.req("pwd")

    s.req_ok("cd /")

    assert_equal "/", s.req("pwd")

    err = s.req("cd /this-better-be-totally-non-existent-on-any-system-#{rand}")
    assert_match(%r{\AERR }, err, err)

    assert_equal "/", s.req("pwd")
  end

  def test_state_file
    state = Tempfile.new(%w(state .yml))
    state_path = state.path
    state.close!
    s = client_socket
    s.req_ok(%W(state dump #{state_path}))
    hash = YAML.load(IO.binread(state_path))
    assert_equal @sock_path, hash["socket"]
    assert_equal "default", hash["sinks"][0]["name"]

    assert_equal "", IO.binread(@state_tmp.path)
    s.req_ok(%W(state dump))
    orig = YAML.load(IO.binread(@state_tmp.path))
    assert_equal orig, hash
  ensure
    File.unlink(state_path)
  end

  def test_source_ed
    s = client_socket
    assert_equal "sox av ff splitfx", s.req("source ls")
    s.req_ok("source ed av tryorder=-1")
    assert_equal "av sox ff splitfx", s.req("source ls")
    s.req_ok("source ed av tryorder=")
    assert_equal "sox av ff splitfx", s.req("source ls")

    s.req_ok("source ed sox command=true")
    sox = YAML.load(s.req("source cat sox"))
    assert_equal "true", sox["command"]

    s.req_ok("source ed sox command=")
    sox = YAML.load(s.req("source cat sox"))
    assert_equal DTAS::Source::Sox::SOX_DEFAULTS["command"], sox["command"]
  end
end

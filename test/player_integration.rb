# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'dtas/player'
require 'dtas/state_file'
require 'dtas/unix_client'
require 'tempfile'
require 'shellwords'
require 'timeout'

module PlayerIntegration
  def setup
    sock_tmp = Tempfile.new(%w(dtas-test .sock))
    @state_tmp = Tempfile.new(%w(dtas-test .yml))
    @sock_path = sock_tmp.path
    sock_tmp.close!
    @player = DTAS::Player.new
    @player.socket = @sock_path
    @player.state_file = DTAS::StateFile.new(@state_tmp.path)
    @player.bind
    @out = Tempfile.new(%w(dtas-test .out))
    @err = Tempfile.new(%w(dtas-test .err))
    @out.sync = @err.sync = true
    @pid = fork do
      at_exit { @player.close }
      ENV["SOX_OPTS"] = "#{ENV['SOX_OPTS']} -R"
      unless $DEBUG
        $stdout.reopen(@out)
        $stderr.reopen(@err)
      end
      @player.run
    end

    # null playback device with delay to simulate a real device
    @fmt = DTAS::Format.new
    @period = 0.01
    @period_size = @fmt.bytes_per_sample * @fmt.channels * @fmt.rate * @period
    @cmd = "exec 2>/dev/null " \
           "ruby -e " \
           "\"b=%q();loop{STDIN.readpartial(#@period_size,b);sleep(#@period)}\""

    # FIXME gross...
    @player.instance_eval do
      @sink_buf.close!
    end
  end

  def client_socket
    DTAS::UNIXClient.new(@sock_path)
  end

  def wait_pid_dead(pid, time = 5)
    Timeout.timeout(time) do
      begin
        Process.kill(0, pid)
        sleep(0.01)
      rescue Errno::ESRCH
        return
      end while true
    end
  end

  def wait_files_not_empty(*files)
    files = Array(files)
    Timeout.timeout(5) { sleep(0.01) until files.all? { |f| f.size > 0 } }
  end

  def default_sink_pid(s)
    default_pid = Tempfile.new(%w(dtas-test .pid))
    pf = "echo $$ >> #{default_pid.path}; "
    s.req_ok("sink ed default command='#{pf}#@cmd'")
    default_pid
  end

  def teardown
    if @pid
      Process.kill(:TERM, @pid)
      Process.waitpid2(@pid)
    end
    refute File.exist?(@sock_path)
    @state_tmp.close!
    @out.close! if @out
    @err.close! if @err
  end

  def read_pid_file(file)
    file.rewind
    pid = file.read.to_i
    assert_operator pid, :>, 0
    pid
  end

  def tmp_noise(len = 5)
    noise = Tempfile.open(%w(junk .sox))
    cmd = %W(sox -R -n -r44100 -c2 #{noise.path} synth #{len} pluck)
    assert system(*cmd), cmd.inspect
    [ noise, len ]
  end

  def dethrottle_decoder(s)
    s.req_ok("sink ed default active=false")
  end

  def stop_playback(pid_file, s)
    s.req_ok("skip")
    pid = read_pid_file(pid_file)
    wait_pid_dead(pid)
  end
end

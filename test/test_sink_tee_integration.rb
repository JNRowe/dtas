# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require './test/player_integration'
class TestSinkTeeIntegration < Testcase
  include PlayerIntegration

  def test_tee_integration
    s = client_socket
    default_sink_pid(s)
    tee_pid = Tempfile.new(%w(dtas-test .pid))
    orig = Tempfile.new(%w(orig .junk))
    ajunk = Tempfile.new(%w(a .junk))
    bjunk = Tempfile.new(%w(b .junk))
    cmd = "echo $$ > #{tee_pid.path}; " \
          "cat /dev/fd/a > #{ajunk.path} & " \
          "cat /dev/fd/b > #{bjunk.path}; wait"
    s.req_ok("sink ed split active=true command='#{cmd}'")
    pluck = "sox -n $SOXFMT - synth 3 pluck | tee #{orig.path}"
    s.req_ok("enq-cmd \"#{pluck}\"")

    wait_files_not_empty(tee_pid)
    pid = read_pid_file(tee_pid)
    dethrottle_decoder(s)
    wait_pid_dead(pid)
    assert_equal ajunk.size, bjunk.size
    assert_equal orig.size, bjunk.size
    assert_equal ajunk.read, bjunk.read
    bjunk.rewind
    assert_equal orig.read, bjunk.read
  end
end

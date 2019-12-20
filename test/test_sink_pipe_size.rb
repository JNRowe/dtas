# Copyright (C) 2013-2019 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/player_integration'
class TestSinkPipeSizeIntegration < Testcase
  include PlayerIntegration

  def test_sink_pipe_size_integration
    s = client_socket
    default_sink_pid(s)
    s.req_ok("sink ed default pipe_size=0x1000")
    s.req_ok("sink ed default pipe_size=0x10000")
    s.req_ok("sink ed default pipe_size=")
    s.req_ok("sink ed default pipe_size=4096")
  end
end if RUBY_PLATFORM =~ /linux/i &&
      File.readable?('/proc/sys/fs/pipe-max-size')

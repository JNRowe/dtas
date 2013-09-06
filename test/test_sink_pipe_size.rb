# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
begin
  require 'io/splice'
  require './test/player_integration'
  class TestSinkPipeSizeIntegration < Testcase
    include PlayerIntegration

    def test_sink_pipe_size_integration
      s = client_socket
      default_sink_pid(s)
      s.req_ok("sink ed default pipe_size=0x1000")
      s.req_ok("sink ed default pipe_size=0x10000")
      assert_match %r{\AERR }, s.req("sink ed default pipe_size=")
      s.req_ok("sink ed default pipe_size=4096")
    end if IO.method_defined?(:pipe_size=)
  end
rescue LoadError
end

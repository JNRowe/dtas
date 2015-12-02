# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative 'helper'
require 'socket'
require 'dtas/mpd_emu_client'
require 'dtas/server_loop'

class TestMlib < Testcase
  class Quit
    attr_reader :to_io

    def initialize
      @to_io, @w = IO.pipe
    end

    def quit!
      @w.close
    end

    def accept_nonblock(*args)
      Thread.exit
    end
  end

  def setup
    @host = '127.0.0.1'
    @l = TCPServer.new(@host, 0)
    @port = @l.addr[1]
    @quit = Quit.new
    @klass = Class.new(DTAS::MpdEmuClient)
    @svc = DTAS::ServerLoop.new([@l, @quit], @klass)
    @th = Thread.new { @svc.run_forever }
    @c = TCPSocket.new(@host, @port)
    assert_match %r{\AOK.*MPD.*\n\z}, @c.gets
  end

  def teardown
    @quit.quit!
    @th.join
    @quit.to_io.close
    @l.close
    @c.close unless @c.closed?
  end

  def test_ping
    @c.write "ping\n"
    assert_equal "OK\n", @c.gets
    assert_nil IO.select([@c], nil, nil, 0)
  end

  # to ensure output buffering works:
  module BigOutput
    WAKE = IO.pipe
    NR = 20000
    OMG = ('OMG! ' * 99) << "OMG!\n"
    def mpdcmd_big_output(*_)
      rv = true
      NR.times { rv = out(OMG) }
      # tell the tester we're done writing to our buffer:
      WAKE[1].write(rv == :wait_writable ? '.' : 'F')
      rv
    end
  end

  def test_big_output
    @klass.__send__(:include, BigOutput)
    @c.write "big_output\n"
    assert_equal '.', BigOutput::WAKE[0].read(1), 'server blocked on write'
    BigOutput::NR.times do
      assert_equal BigOutput::OMG, @c.gets
    end
  end
end

# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'socket'
require 'io/wait'

# an accepted (client) socket in dtas-player server
class DTAS::UNIXAccepted # :nodoc:
  attr_reader :to_io

  def initialize(sock)
    @to_io = sock
    @sbuf = []
  end

  # public API (for DTAS::Player)
  # returns :wait_readable on success
  def emit(msg)
    if @sbuf.empty?
      case rv = @to_io.sendmsg_nonblock(msg, Socket::MSG_EOR, exception: false)
      when :wait_writable
        @sbuf << msg
        rv
      else
        :wait_readable
      end
    else
      @sbuf << msg
      :wait_writable
    end
  rescue => e
    e
  end

  # flushes pending data if it got buffered
  def writable_iter
    case @to_io.sendmsg_nonblock(@sbuf[0], Socket::MSG_EOR, exception: false)
    when :wait_writable then return :wait_writable
    else
      @sbuf.shift
      @sbuf.empty? ? :wait_readable : :wait_writable
    end
  rescue => e
    e
  end

  def readable_iter
    nread = @to_io.nread

    # EOF, assume no spurious wakeups for SOCK_SEQPACKET
    return nil if nread == 0

    case msg = @to_io.recv_nonblock(nread, exception: false)
    when :wait_readable then return msg
    when '', nil then return nil # EOF
    else
      yield(self, msg) # DTAS::Player deals with this
    end
    @sbuf.empty? ? :wait_readable : :wait_writable
  rescue SystemCallError
    nil
  end

  def close
    @to_io.close
  end

  def closed?
    @to_io.closed?
  end
end

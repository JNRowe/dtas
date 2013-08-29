# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'socket'
require 'io/wait'

class DTAS::UNIXAccepted # :nodoc:
  attr_reader :to_io

  def initialize(sock)
    @to_io = sock
    @send_buf = []
  end

  # public API (for DTAS::Player)
  # returns :wait_readable on success
  def emit(msg)
    buffered = @send_buf.size
    if buffered == 0
      begin
        @to_io.sendmsg_nonblock(msg, Socket::MSG_EOR)
        return :wait_readable
      rescue Errno::EAGAIN
        @send_buf << msg
        return :wait_writable
      rescue => e
        return e
      end
    elsif buffered > 100
      return RuntimeError.new("too many messages buffered")
    else # buffered > 0
      @send_buf << msg
      return :wait_writable
    end
  end

  # flushes pending data if it got buffered
  def writable_iter
    begin
      msg = @send_buf.shift or return :wait_readable
      @to_io.send_nonblock(msg, Socket::MSG_EOR)
    rescue Errno::EAGAIN
      @send_buf.unshift(msg)
      return :wait_writable
    rescue => e
      return e
    end while true
  end

  def readable_iter
    io = @to_io
    nread = io.nread

    # EOF, assume no spurious wakeups for SOCK_SEQPACKET
    return nil if nread == 0

    begin
      begin
        msg, _, _ = io.recvmsg_nonblock(nread)
      rescue EOFError, SystemCallError
        return nil
      end
      yield(self, msg) # DTAS::Player deals with this
      nread = io.nread
    end while nread > 0
    :wait_readable
  end

  def close
    @to_io.close
  end

  def closed?
    @to_io.closed?
  end
end

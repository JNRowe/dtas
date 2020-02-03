# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'socket'
require 'io/wait'

# an accepted (client) socket in dtas-player server
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
      case rv = sendmsg_nonblock(msg)
      when :wait_writable
        @send_buf << msg
        rv
      else
        :wait_readable
      end
    else # buffered > 0
      @send_buf << msg
      :wait_writable
    end
  rescue => e
    e
  end

  # flushes pending data if it got buffered
  def writable_iter
    case sendmsg_nonblock(@send_buf[0])
    when :wait_writable then return :wait_writable
    else
      @send_buf.shift
      @send_buf.empty? ? :wait_readable : :wait_writable
    end
  rescue => e
    e
  end

  def readable_iter
    nread = @to_io.nread

    # EOF, assume no spurious wakeups for SOCK_SEQPACKET
    return nil if nread == 0

    case msg = recv_nonblock(nread)
    when :wait_readable then return msg
    when '', nil then return nil # EOF
    else
      yield(self, msg) # DTAS::Player deals with this
    end
    @send_buf.empty? ? :wait_readable : :wait_writable
  rescue SystemCallError
    nil
  end

  def close
    @to_io.close
  end

  def closed?
    @to_io.closed?
  end

  if RUBY_VERSION.to_f >= 2.3
    def sendmsg_nonblock(msg)
      @to_io.sendmsg_nonblock(msg, Socket::MSG_EOR, exception: false)
    end

    def recv_nonblock(len)
      @to_io.recv_nonblock(len, exception: false)
    end
  else
    def sendmsg_nonblock(msg)
      @to_io.sendmsg_nonblock(msg, Socket::MSG_EOR)
    rescue IO::WaitWritable
      :wait_writable
    end

    def recv_nonblock(len)
      @to_io.recv_nonblock(len)
    rescue IO::WaitReadable
      :wait_readable
    rescue EOFError
      nil
    end
  end
end

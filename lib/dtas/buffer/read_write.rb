# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'io/nonblock'
require_relative '../../dtas'
require_relative '../pipe'
require_relative '../nonblock'

# compatibility code for systems lacking "splice" support via the
# "io-splice" RubyGem.  Used only by -player
module DTAS::Buffer::ReadWrite # :nodoc:
  MAX_AT_ONCE = 512 # min PIPE_BUF value in POSIX
  attr_accessor :buffer_size

  def _rbuf
    Thread.current[:dtas_pbuf] ||= ''.b
  end

  # be sure to only call this with nil when all writers to @wr are done
  def discard(bytes)
    buf = _rbuf
    begin
      @to_io.readpartial(bytes, buf)
      bytes -= buf.bytesize
    rescue EOFError
      return
    end until bytes == 0
  end

  # always block when we have a single target
  def broadcast_one(targets, limit = nil)
    buf = _rbuf
    case rv = @to_io.read_nonblock(limit || MAX_AT_ONCE, buf, exception: false)
    when nil, :wait_readable then return rv
    end
    n = targets[0].write(buf) # IO#write has write-in-full behavior
    @bytes_xfer += n
    :wait_readable
  rescue Errno::EPIPE, IOError => e
    __dst_error(targets[0], e)
    targets.clear
    nil # do not return error here, we already spewed an error message
  end

  def broadcast_inf(targets, limit = nil)
    nr_nb = targets.count(&:nonblock?)
    if nr_nb == 0 || nr_nb == targets.size
      # if all targets are full, don't start until they're all writable
      r = IO.select(nil, targets, nil, 0) or return targets
      blocked = targets - r[1]

      # tell DTAS::UNIXServer#run_once to wait on the blocked targets
      return blocked if blocked[0]

      # all writable, yay!
    else
      blocked = []
    end

    again = {}

    # don't pin too much on one target
    bytes = inflight
    limit ||= MAX_AT_ONCE
    bytes = bytes > limit ? limit : bytes
    buf = _rbuf
    @to_io.read(bytes, buf)
    n = buf.bytesize
    @bytes_xfer += n

    targets.delete_if do |dst|
      begin
        if dst.nonblock?
          case w = dst.write_nonblock(buf, exception: false)
          when :wait_writable
            blocked << dst
          else
            again[dst] = buf.byteslice(w, n) if w < n
          end
        else
          dst.write(buf)
        end
        false
      rescue IOError, Errno::EPIPE => e
        again.delete(dst)
        __dst_error(dst, e)
        true
      end
    end

    # try to write as much as possible
    again.delete_if do |dst, sbuf|
      begin
        case w = dst.write_nonblock(sbuf, exception: false)
        when :wait_writable
          blocked << dst
          true
        else
          n = sbuf.bytesize
          if w < n
            again[dst] = sbuf.byteslice(w, n)
            false
          else
            true
          end
        end
      rescue IOError, Errno::EPIPE => e
        __dst_error(dst, e)
        true
      end
    end until again.empty?
    targets[0] ? :wait_readable : nil
  end
end

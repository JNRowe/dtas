# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'io/nonblock'
require 'fiddle' # require_relative caller should expect LoadError
require_relative '../../dtas'
require_relative '../pipe'

# Used by -player on Linux systems with the "splice" syscall
module DTAS::Buffer::FiddleSplice # :nodoc:
  MAX_AT_ONCE = 4096 # page size in Linux
  MAX_AT_ONCE_1 = 65536
  F_MOVE = 1
  F_NONBLOCK = 2

  Splice = Fiddle::Function.new(DTAS.libc['splice'], [
      Fiddle::TYPE_INT, # int fd_in,
      Fiddle::TYPE_VOIDP, # loff_t *off_in
      Fiddle::TYPE_INT, # int fd_out
      Fiddle::TYPE_VOIDP, # loff_t *off_out
      Fiddle::TYPE_SIZE_T, # size_t len
      Fiddle::TYPE_INT, # unsigned int flags
    ],
    Fiddle::TYPE_SSIZE_T) # ssize_t

  Tee = Fiddle::Function.new(DTAS.libc['tee'], [
      Fiddle::TYPE_INT, # int fd_in,
      Fiddle::TYPE_INT, # int fd_out
      Fiddle::TYPE_SIZE_T, # size_t len
      Fiddle::TYPE_INT, # unsigned int flags
    ],
    Fiddle::TYPE_SSIZE_T) # ssize_t

  def _syserr(s, func)
    raise "BUG: we should not encounter EOF on #{func}" if s == 0
    case errno = Fiddle.last_error
    when Errno::EAGAIN::Errno
      return :EAGAIN
    when Errno::EPIPE::Errno
      raise Errno::EPIPE.exception
    when Errno::EINTR::Errno
      return nil
    else
      raise SystemCallError, "#{func} error: #{errno}"
    end
  end

  def splice(src, dst, len, flags)
    begin
      s = Splice.call(src.fileno, nil, dst.fileno, nil, len, flags)
      return s if s > 0
      sym = _syserr(s, 'splice') and return sym
    end while true
  end

  def tee(src, dst, len, flags = 0)
    begin
      s = Tee.call(src.fileno, dst.fileno, len, flags)
      return s if s > 0
      sym = _syserr(s, 'tee') and return sym
    end while true
  end

  def buffer_size
    @to_io.pipe_size
  end

  # nil is OK, won't reset existing pipe, either...
  def buffer_size=(bytes)
    @to_io.pipe_size = bytes if bytes
    @buffer_size = bytes
  end

  # be sure to only call this with nil when all writers to @wr are done
  def discard(bytes)
    splice(@to_io, DTAS.null, bytes, 0)
  end

  def broadcast_one(targets, limit = nil)
    # single output is always non-blocking
    limit ||= MAX_AT_ONCE_1
    s = splice(@to_io, targets[0], limit, F_MOVE|F_NONBLOCK)
    if Symbol === s
      targets # our one and only target blocked on write
    else
      @bytes_xfer += s
      :wait_readable # we want to read more from @to_io soon
    end
  rescue Errno::EPIPE, IOError => e
    __dst_error(targets[0], e)
    targets.clear
    nil # do not return error here, we already spewed an error message
  end

  def __tee_in_full(src, dst, bytes)
    rv = 0
    while bytes > 0
      s = tee(src, dst, bytes)
      bytes -= s
      rv += s
    end
    rv
  end

  def __splice_in_full(src, dst, bytes, flags)
    rv = 0
    while bytes > 0
      s = splice(src, dst, bytes, flags)
      rv += s
      bytes -= s
    end
    rv
  end

  # returns the largest value we teed
  def __broadcast_tee(blocked, targets, chunk_size)
    most_teed = 0
    targets.delete_if do |dst|
      begin
        t = (dst.nonblock? || most_teed == 0) ?
              tee(@to_io, dst, chunk_size, F_NONBLOCK) :
              __tee_in_full(@to_io, dst, chunk_size)
        if Integer === t
          if t > most_teed
            chunk_size = t if most_teed == 0
            most_teed = t
          end
        else
          blocked << dst
        end
        false
      rescue IOError, Errno::EPIPE => e
        __dst_error(dst, e)
        true
      end
    end
    most_teed
  end

  def broadcast_inf(targets, limit = nil)
    if targets.all?(&:ready_write_optimized?)
      blocked = []
    elsif targets.none?(&:nonblock?)
      # if all targets are blocking, don't start until they're all writable
      r = IO.select(nil, targets, nil, 0) or return targets
      blocked = targets - r[1]

      # tell DTAS::UNIXServer#run_once to wait on the blocked targets
      return blocked if blocked[0]

      # all writable, yay!
    else
      blocked = []
    end

    # don't pin too much on one target
    bytes = limit || MAX_AT_ONCE
    last = targets.pop # we splice to the last one, tee to the rest

    # this may return zero if all targets were non-blocking
    most_teed = __broadcast_tee(blocked, targets, bytes)

    # don't splice more than the largest amount we successfully teed
    bytes = most_teed if most_teed > 0

    begin
      targets << last
      if last.nonblock? || most_teed == 0
        s = splice(@to_io, last, bytes, F_MOVE|F_NONBLOCK)
        if Symbol === s
          blocked << last

          # we accomplished nothing!
          # If _all_ writers are blocked, do not discard data,
          # stay blocked on :wait_writable
          return blocked if most_teed == 0

          # the tees targets win, drop data intended for last
          if most_teed > 0
            discard(most_teed)
            @bytes_xfer += most_teed
            # do not watch for writability of last, last is non-blocking
            return :wait_readable
          end
        end
      else
        # the blocking case is simple
        s = __splice_in_full(@to_io, last, bytes, F_MOVE)
      end
      @bytes_xfer += s

      # if we can't splice everything
      # discard it so the early targets do not get repeated data
      if s < bytes && most_teed > 0
        discard(bytes - s)
      end
      :wait_readable
    rescue IOError, Errno::EPIPE => e # last failed, drop it
      __dst_error(last, e)
      targets.pop # we're no longer a valid target

      if most_teed == 0
        # nothing accomplished, watch any targets
        return blocked if blocked[0]
      else
        # some progress, discard the data we could not splice
        @bytes_xfer += most_teed
        discard(most_teed)
      end

      # stop decoding if we're completely errored out
      # returning nil will trigger close
      return targets[0] ? :wait_readable : nil
    end
  end
end

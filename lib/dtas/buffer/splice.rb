# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'io/nonblock'
require 'io/splice'
require_relative '../../dtas'
require_relative '../pipe'

module DTAS::Buffer::Splice # :nodoc:
  MAX_AT_ONCE = 4096 # page size in Linux
  MAX_AT_ONCE_1 = 65536
  MAX_SIZE = File.read("/proc/sys/fs/pipe-max-size").to_i
  DEVNULL = File.open("/dev/null", "r+")
  F_MOVE = IO::Splice::F_MOVE
  WAITALL = IO::Splice::WAITALL

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
    IO.splice(@to_io, nil, DEVNULL, nil, bytes)
  end

  def broadcast_one(targets)
    # single output is always non-blocking
    s = IO.trysplice(@to_io, nil, targets[0], nil, MAX_AT_ONCE_1, F_MOVE)
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

  # returns the largest value we teed
  def __broadcast_tee(blocked, targets, chunk_size)
    most_teed = 0
    targets.delete_if do |dst|
      begin
        t = (dst.nonblock? || most_teed == 0) ?
            IO.trytee(@to_io, dst, chunk_size) :
            IO.tee(@to_io, dst, chunk_size, WAITALL)
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

  def broadcast_inf(targets)
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
    bytes = MAX_AT_ONCE
    last = targets.pop # we splice to the last one, tee to the rest

    # this may return zero if all targets were non-blocking
    most_teed = __broadcast_tee(blocked, targets, bytes)

    # don't splice more than the largest amount we successfully teed
    bytes = most_teed if most_teed > 0

    begin
      targets << last
      if last.nonblock? || most_teed == 0
        s = IO.trysplice(@to_io, nil, last, nil, bytes, F_MOVE)
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
        s = IO.splice(@to_io, nil, last, nil, bytes, WAITALL|F_MOVE)
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

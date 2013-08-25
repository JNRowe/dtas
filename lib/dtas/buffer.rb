# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'

class DTAS::Buffer # :nodoc:
  begin
    raise LoadError, "no splice with _DTAS_POSIX" if ENV["_DTAS_POSIX"]
    require 'io/splice' # splice is only in Linux for now...
    require_relative 'buffer/splice'
    include DTAS::Buffer::Splice
  rescue LoadError
    require_relative 'buffer/read_write'
    include DTAS::Buffer::ReadWrite
  end

  attr_reader :to_io # call nread on this
  attr_reader :wr # processes (sources) should redirect to this
  attr_accessor :bytes_xfer

  def initialize
    @bytes_xfer = 0
    @buffer_size = nil
    @to_io, @wr = DTAS::Pipe.new
  end

  def self.load(hash)
    buf = new
    if hash
      bs = hash["buffer_size"] and buf.buffer_size = bs
    end
    buf
  end

  def to_hsh
    @buffer_size ? { "buffer_size" => @buffer_size } : {}
  end

  def __dst_error(dst, e)
    warn "dropping #{dst.inspect} due to error: #{e.message} (#{e.class})"
    dst.close unless dst.closed?
  end

  # This will modify targets
  # returns one of:
  # - :wait_readable
  # - subset of targets array for :wait_writable
  # - some type of StandardError
  # - nil
  def broadcast(targets)
    bytes = inflight
    return :wait_readable if 0 == bytes # spurious wakeup

    case targets.size
    when 0
      :ignore # this will pause decoders
    when 1
      broadcast_one(targets, bytes)
    else # infinity
      broadcast_inf(targets, bytes)
    end
  end

  def readable_iter
    # this calls DTAS::Buffer#broadcast from DTAS::Player
    yield(self, nil)
  end

  def inflight
    @to_io.nread
  end

  # don't really close the pipes under normal circumstances, just clear data
  def close
    bytes = inflight
    discard(bytes) if bytes > 0
  end

  def buf_reset
    close!
    @bytes_xfer = 0
    @to_io, @wr = DTAS::Pipe.new
    @wr.pipe_size = @buffer_size if @buffer_size
  end

  def close!
    @to_io.close
    @wr.close
  end
end

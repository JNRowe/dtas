# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'socket'
require_relative '../dtas'
require_relative 'unix_accepted'

# This uses SOCK_SEQPACKET, unlike ::UNIXServer in Ruby stdlib

# The programming model for the event loop here aims to be compatible
# with EPOLLONESHOT use with epoll, since that fits my brain far better
# than existing evented APIs/frameworks.
# If we cared about scalability to thousands of clients, we'd really use epoll,
# but IO.select can be just as fast (or faster) with few descriptors and
# is obviously more portable.

class DTAS::UNIXServer # :nodoc:
  attr_reader :to_io

  def close
    File.unlink(@path)
    @to_io.close
  end

  def initialize(path)
    @path = path
    # lock down access by default, arbitrary commands may run as the
    # same user dtas-player runs as:
    old_umask = File.umask(0077)
    @to_io = Socket.new(:UNIX, :SEQPACKET, 0)
    addr = Socket.pack_sockaddr_un(path)
    begin
      @to_io.bind(addr)
    rescue Errno::EADDRINUSE
      # maybe we have an old path leftover from a killed process
      tmp = Socket.new(:UNIX, :SEQPACKET, 0)
      begin
        tmp.connect(addr)
        raise RuntimeError, "socket `#{path}' is in use", []
      rescue Errno::ECONNREFUSED
        # ok, leftover socket, unlink and rebind anyways
        File.unlink(path)
        @to_io.bind(addr)
      ensure
        tmp.close
      end
    end
    @to_io.listen(1024)
    @readers = { self => true }
    @writers = {}
  ensure
    File.umask(old_umask)
  end

  def write_failed(client, e)
    warn "failed to write to #{client}: #{e.message} (#{e.class})"
    client.close
  end

  def readable_iter
    # we do not do anything with the block passed to us
    begin
      sock, _ = @to_io.accept_nonblock
      @readers[DTAS::UNIXAccepted.new(sock)] = true
    rescue Errno::ECONNABORTED # ignore this, it happens
    rescue Errno::EAGAIN
      return :wait_readable
    end while true
  end

  def wait_ctl(io, err)
    case err
    when :wait_readable
      @readers[io] = true
    when :wait_writable
      @writers[io] = true
    when :delete
      @readers.delete(io)
      @writers.delete(io)
    when :ignore
      # There are 2 cases for :ignore
      # - DTAS::Buffer was readable before, but all destinations (e.g. sinks)
      #   were blocked, so we stop caring for producer (buffer) readability.
      # - a consumer (e.g. DTAS::Sink) just became writable, but the
      #   corresponding DTAS::Buffer was already readable in a previous
      #   call.
    when nil
      io.close
    when StandardError
      io.close
    else
      raise "BUG: wait_ctl invalid: #{io} #{err.inspect}"
    end
  end

  def run_once
    # give IO.select one-shot behavior, snapshot and replace the watchlist
    r = IO.select(@readers.keys, @writers.keys) or return
    r[1].each do |io|
      @writers.delete(io)
      wait_ctl(io, io.writable_iter)
    end
    r[0].each do |io|
      @readers.delete(io)
      wait_ctl(io, io.readable_iter { |_io, msg| yield(_io, msg) })
    end
  end
end

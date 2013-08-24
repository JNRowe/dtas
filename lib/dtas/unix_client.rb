# -*- encoding: binary -*-
# :stopdoc:
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'dtas'
require 'socket'
require 'io/wait'
require 'shellwords'

class DTAS::UNIXClient
  attr_reader :to_io

  def self.default_path
    (ENV["DTAS_PLAYER_SOCK"] || File.expand_path("~/.dtas/player.sock")).b
  end

  def initialize(path = self.class.default_path)
    @to_io = begin
      raise if ENV["_DTAS_NOSEQPACKET"]
      Socket.new(:AF_UNIX, :SOCK_SEQPACKET, 0)
    rescue
      warn("get your operating system developers to support " \
           "SOCK_SEQPACKET for AF_UNIX sockets")
      warn("falling back to SOCK_DGRAM, reliability possibly compromised")
      Socket.new(:AF_UNIX, :SOCK_DGRAM, 0)
    end
    @to_io.connect(Socket.pack_sockaddr_un(path))
  end

  def req_start(args)
    args = Shellwords.join(args) if Array === args
    @to_io.send(args, Socket::MSG_EOR)
  end

  def req_ok(args, timeout = nil)
    res = req(args, timeout)
    res == "OK" or raise "Unexpected response: #{res}"
    res
  end

  def req(args, timeout = nil)
    req_start(args)
    res_wait(timeout)
  end

  def res_wait(timeout = nil)
    @to_io.wait(timeout)
    nr = @to_io.nread
    nr > 0 or raise EOFError, "unexpected EOF from server"
    @to_io.recvmsg[0]
  end
end

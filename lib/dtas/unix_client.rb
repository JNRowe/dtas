# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'
require_relative 'xs'
require 'socket'
require 'io/wait'
require 'shellwords'

# a socket connection used by dtas-player clients (e.g. dtas-ctl)
class DTAS::UNIXClient # :nodoc:
  attr_reader :to_io

  include DTAS::XS

  def self.default_path
    (ENV["DTAS_PLAYER_SOCK"] || File.expand_path("~/.dtas/player.sock"))
  end

  def initialize(path = self.class.default_path)
    @to_io = Socket.new(:UNIX, :SEQPACKET, 0)
    @to_io.connect(Socket.pack_sockaddr_un(path))
  end

  def req_start(args)
    args = xs(args) if Array === args
    @to_io.send(args, 0)
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
    @to_io.wait_readable(timeout)
    nr = @to_io.nread
    nr > 0 or raise EOFError, "unexpected EOF from server"
    @to_io.recv(nr)
  end
end

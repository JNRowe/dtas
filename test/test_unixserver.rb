# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'tempfile'
require 'dtas/unix_server'
require 'stringio'

class TestUNIXServer < Minitest::Unit::TestCase
  def setup
    @tmp = Tempfile.new(%w(dtas-unix_server-test .sock))
    File.unlink(@tmp.path)
    @clients = []
    @srv = DTAS::UNIXServer.new(@tmp.path)
  end

  def test_close
    assert File.exist?(@tmp.path)
    assert_nil @srv.close
    refute File.exist?(@tmp.path)
  end

  def teardown
    @clients.each { |io| io.close unless io.closed? }
    if File.exist?(@tmp.path)
      @tmp.close!
    else
      @tmp.close
    end
  end

  def new_client
    c = Socket.new(:AF_UNIX, :SEQPACKET, 0)
    @clients << c
    c.connect(Socket.pack_sockaddr_un(@tmp.path))
    c
  end

  def test_server_loop
    client = new_client
    @srv.run_once # nothing
    msgs = []
    clients = []
    client.send("HELLO", Socket::MSG_EOR)
    @srv.run_once do |c, msg|
      clients << c
      msgs << msg
    end
    assert_equal %w(HELLO), msgs, clients.inspect
    assert_equal 1, clients.size
    c = clients[0]
    c.emit "HIHI"
    assert_equal "HIHI", client.recv(4)

    err = nil
    500.times do
      rc = c.emit "SPAM"
      case rc
      when StandardError
        err = rc
        break
      end
    end
    assert_kind_of RuntimeError, err
  end
end

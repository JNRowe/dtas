# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require './test/helper'
require 'stringio'
require 'dtas/buffer'

class TestBuffer < Testcase
  def teardown
    @to_close.each { |io| io.close unless io.closed? }
  end

  def setup
    @to_close = []
  end

  def pipe
    ret = IO.pipe
    ret.each do |x|
      def x.ready_write_optimized?
        false
      end
    end
    @to_close.concat(ret)
    ret
  end

  def tmperr
    olderr = $stderr
    $stderr = newerr = StringIO.new
    yield
    newerr
  ensure
    $stderr = olderr
  end

  def new_buffer
    buf = DTAS::Buffer.new
    @to_close << buf.to_io
    @to_close << buf.wr
    buf
  end

  def test_set_buffer_size
    buf = new_buffer
    buf.buffer_size = DTAS::Buffer::MAX_SIZE
    assert_equal DTAS::Buffer::MAX_SIZE, buf.buffer_size
  end if defined?(DTAS::Buffer::MAX_SIZE)

  def test_buffer_size
    buf = new_buffer
    assert_operator buf.buffer_size, :>, 128
    buf.buffer_size = DTAS::Buffer::MAX_SIZE
    assert_equal DTAS::Buffer::MAX_SIZE, buf.buffer_size
  end if defined?(DTAS::Buffer::MAX_SIZE)

  def test_broadcast_1
    buf = new_buffer
    r, w = IO.pipe
    buf.wr.write "HIHI"
    assert_equal :wait_readable, buf.broadcast([w])
    assert_equal 4, buf.bytes_xfer
    tmp = [w]
    r.close
    buf.wr.write "HIHI"
    newerr = tmperr { assert_nil buf.broadcast(tmp) }
    assert_equal [], tmp
    assert_match(%r{dropping}, newerr.string)
  end

  def test_broadcast_tee
    buf = new_buffer
    return unless buf.respond_to?(:__broadcast_tee)
    blocked = []
    a = pipe
    b = pipe
    buf.wr.write "HELLO"
    assert_equal 4, buf.__broadcast_tee(blocked, [a[1], b[1]], 4)
    assert_empty blocked
    assert_equal "HELL", a[0].read(4)
    assert_equal "HELL", b[0].read(4)
    assert_equal 5, buf.__broadcast_tee(blocked, [a[1], b[1]], 5)
    assert_empty blocked
    assert_equal "HELLO", a[0].read(5)
    assert_equal "HELLO", b[0].read(5)
    max = '*' * a[0].pipe_size
    assert_equal max.size, a[1].write(max)
    assert_equal a[0].nread, a[0].pipe_size
    a[1].nonblock = true
    assert_equal 5, buf.__broadcast_tee(blocked, [a[1], b[1]], 5)
    assert_equal [a[1]], blocked
    a[1].nonblock = false
    b[0].read(b[0].nread)
    b[1].write(max)
  end

  def test_broadcast
    a = pipe
    b = pipe
    buf = new_buffer
    buf.wr.write "HELLO"
    assert_equal :wait_readable, buf.broadcast([a[1], b[1]])
    assert_equal 5, buf.bytes_xfer
    assert_equal "HELLO", a[0].read(5)
    assert_equal "HELLO", b[0].read(5)

    return unless b[1].respond_to?(:pipe_size)

    b[1].nonblock = true
    b[1].write('*' * b[1].pipe_size)
    buf.wr.write "BYE"
    assert_equal :wait_readable, buf.broadcast([a[1], b[1]])
    assert_equal 8, buf.bytes_xfer

    buf.wr.write "DROP"
    b[0].close
    tmp = [a[1], b[1]]
    newerr = tmperr { assert_equal :wait_readable, buf.broadcast(tmp) }
    assert_equal 12, buf.bytes_xfer
    assert_equal [a[1]], tmp
    assert_match(%r{dropping}, newerr.string)
  end

  def test_broadcast_total_fail
    a = pipe
    b = pipe
    buf = new_buffer
    buf.wr.write "HELLO"
    a[0].close
    b[0].close
    tmp = [a[1], b[1]]
    newerr = tmperr { assert_nil buf.broadcast(tmp) }
    assert_equal [], tmp
    assert_match(%r{dropping}, newerr.string)
  end

  def test_broadcast_mostly_fail
    a = pipe
    b = pipe
    c = pipe
    buf = new_buffer
    buf.wr.write "HELLO"
    b[0].close
    c[0].close
    tmp = [a[1], b[1], c[1]]
    newerr = tmperr { assert_equal :wait_readable, buf.broadcast(tmp) }
    assert_equal 5, buf.bytes_xfer
    assert_equal [a[1]], tmp
    assert_match(%r{dropping}, newerr.string)
  end

  def test_broadcast_all_full
    a = pipe
    b = pipe
    buf = new_buffer
    a[1].write('*' * a[1].pipe_size)
    b[1].write('*' * b[1].pipe_size)

    a[1].nonblock = true
    b[1].nonblock = true
    tmp = [a[1], b[1]]

    buf.wr.write "HELLO"
    assert_equal tmp, buf.broadcast(tmp)
    assert_equal [a[1], b[1]], tmp
  end if IO.method_defined?(:pipe_size)

  def test_serialize
    buf = new_buffer
    hash = buf.to_hsh
    assert_empty hash
    buf.buffer_size = 4096
    hash = buf.to_hsh
    assert_equal %w(buffer_size), hash.keys
    assert_kind_of Integer, hash["buffer_size"]
    assert_operator hash["buffer_size"], :>, 0
  end

  def test_close
    buf = DTAS::Buffer.new
    buf.wr.write "HI"
    assert_equal 2, buf.inflight
    buf.close
    assert_equal 0, buf.inflight
    assert_nil buf.close!
  end

  def test_load_nil
    buf = DTAS::Buffer.load(nil)
    buf.close!
  end

  def test_load_empty
    buf = DTAS::Buffer.load({})
    buf.close!
  end

  def test_load_size
    buf = DTAS::Buffer.load({"buffer_size" => 4096})
    assert_equal 4096, buf.buffer_size
    buf.close!
  end
end

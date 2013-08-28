# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/process'
class TestProcess < Minitest::Unit::TestCase
  include DTAS::Process

  def test_qx_env
    assert_equal "WORLD\n", qx({"HELLO" => "WORLD"}, 'echo $HELLO')
  end

  def test_qx_err
    err = "/dev/null"
    assert_equal "", qx('echo HELLO >&2', err: err)
    assert_equal "/dev/null", err
  end

  def test_qx_err_str
    s = ""
    assert_equal "", qx('echo HELLO >&2', err_str: s)
    assert_equal "HELLO\n", s
  end

  def test_qx_raise
    assert_raises(RuntimeError) { qx('false') }
  end

  def test_qx_no_raise
    status = qx('false', no_raise: true)
    refute status.success?, status.inspect
  end
end

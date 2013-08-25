# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/helper'
require 'dtas/process'
class TestProcess < Minitest::Unit::TestCase
 include DTAS::Process

 def test_qx_env
   assert_equal "WORLD\n", qx({"HELLO" => "WORLD"}, 'echo $HELLO')
 end
end

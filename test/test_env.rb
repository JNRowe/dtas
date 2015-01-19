# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative 'helper'
require 'dtas/process'
class TestEnv < Testcase
  include DTAS::Process
  def setup
    @orig = ENV.to_hash
  end

  def teardown
    ENV.clear
    ENV.update(@orig)
  end

  def test_expand
    ENV["HELLO"] = 'HIHI'
    expect = { "BLAH" => "HIHI/WORLD" }
    opts = {}

    env = { "BLAH" => "$HELLO/WORLD" }
    assert_equal(expect, env_expand(env, opts))

    env = { "BLAH" => "${HELLO}/WORLD" }
    assert_equal(expect, env_expand(env, opts))

    env = { "BLAH" => "$(echo $HELLO)/WORLD" }
    assert_equal(expect, env_expand(env, opts))

    env = { "BLAH" => "`echo $HELLO/WORLD`" }
    assert_equal(expect, env_expand(env, opts))

    env = { "BLAH" => "HIHI/WORLD" }
    assert_equal(expect, env_expand(env, opts))

    # disable expansion
    env = expect = { "BLAH" => "`echo $HELLO/WORLD`" }
    assert_equal(expect, env_expand(env, expand: false))

    # numeric expansion always happens
    env = { "BLAH" => 1 }
    assert_equal({"BLAH"=>"1"}, env_expand(env, expand: false))
    env = { "BLAH" => 1 }
    assert_equal({"BLAH"=>"1"}, env_expand(env, {}))

    expect = { "BLAH" => nil }
    env = expect.dup
    assert_equal expect, env_expand(env, expand:false)
    assert_equal expect, env_expand(env, expand:true)

    # recursive expansion
    res = env_expand({"PATH"=>"$PATH"}, expand: true)
    assert_equal ENV["PATH"], res["PATH"]
  end
end

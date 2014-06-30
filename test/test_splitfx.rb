# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'yaml'
require 'dtas/splitfx'
require 'thread'
require_relative 'helper'

class TestSplitfx < Testcase
  def test_t2s
    sfx = DTAS::SplitFX.new
    sfx.instance_eval do
      @infmt = DTAS::Format.load("rate"=>44100)
    end
    assert_equal 118554000, sfx.t2s_cdda('44:48.3')
    assert_equal 118554030, sfx.t2s('44:48.3')
  end

  def test_example
    hash = YAML.load(File.read("examples/splitfx.sample.yml"))
    sfx = DTAS::SplitFX.new
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # create a guitar pluck
        cmd = '(for n in E2 A2 D3 G3 B3 E4; do '\
               'sox -n -ts32 -c2 -r44100 - synth 4 pluck $n; done ) | ' \
               'sox -ts32 -c2 -r44100 - foo.flac'
        assert system(cmd), cmd.inspect
        sfx.import(hash, {})
        opts = { jobs: nil, silent: true }

        # ensure default FLAC target works
        WAIT_ALL_MTX.synchronize { sfx.run("flac", opts) }
        expect = %w(1.flac 2.flac foo.flac)
        assert_equal expect, Dir["*.flac"].sort

        # compare results with expected output
        res_cmd = "sox 1.flac 2.flac -ts32 -c2 -r44100 result.s32"
        res_pid = fork { exec res_cmd }
        exp_cmd = "sox foo.flac -ts32 -c2 -r44100 expect.s32 trim 4"
        exp_pid = fork { exec exp_cmd }
        _, s = Process.waitpid2(res_pid)
        assert s.success?, "#{res_cmd}: #{s.inspect}"
        _, s = Process.waitpid2(exp_pid)
        assert s.success?, "#{exp_cmd}: #{s.inspect}"
        cmp = "cmp result.s32 expect.s32"
        assert system(cmp), cmp

        # try Ogg Opus, use opusenc/opusdec for now since that's available
        # in Debian 7.0 (sox.git currently has opusfile support, but that
        # hasn't made it into Debian, yet)
        if `which opusenc 2>/dev/null`.size > 0 &&
           `which opusdec 2>/dev/null`.size > 0
          err = $stderr.dup
          begin
            $stderr.reopen("/dev/null", "a")
            WAIT_ALL_MTX.synchronize { sfx.run("opusenc", opts) }
          ensure
            $stderr.reopen(err)
          end

          # ensure opus lengths match flac ones, we decode using opusdec
          # since sox does not yet have opus support in Debian 7.0
          %w(1 2).each do |nr|
            cmd = "opusdec #{nr}.opus #{nr}.wav 2>/dev/null"
            assert system(cmd), cmd
            assert_equal `soxi -D #{nr}.flac`, `soxi -D #{nr}.wav`
          end

          # ensure 16/44.1kHz FLAC works (CDDA-like)
          File.unlink('1.flac', '2.flac')
          WAIT_ALL_MTX.synchronize { sfx.run("flac-cdda", opts) }
          %w(1 2).each do |nr|
            assert_equal `soxi -D #{nr}.flac`, `soxi -D #{nr}.wav`
          end
        end
      end
    end
  end
end

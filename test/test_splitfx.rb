# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'yaml'
require 'dtas/splitfx'
require 'thread'
require_relative 'helper'

class TestSplitfx < Testcase
  include DTAS::SpawnFix

  def tmp_err(path)
    err = $stderr.dup
    $stderr.reopen(path, 'a')
    begin
      yield
    ensure
      $stderr.reopen(err)
      err.close
    end
  end

  def test_t2s
    sfx = DTAS::SplitFX.new
    sfx.instance_eval do
      @infmt = DTAS::Format.load("rate"=>44100)
    end
    assert_equal 118554000, sfx.t2s_cdda('44:48.3')
    assert_equal 118554030, sfx.t2s('44:48.3')
  end

  def assert_contains_stats(file)
    buf = File.read(file)
    [ 'DC offset', 'Min level', 'Max level', 'Pk lev dB',
      'RMS lev dB', 'RMS Pk dB', 'RMS Tr dB', 'Crest factor', 'Flat factor',
      'Pk count', 'Bit-depth', 'Num samples',
      'Length s', 'Scale max', 'Window s'
    ].each do |re|
      assert_match(/^#{re}/, buf, buf)
    end
  end

  def test_example
    hash = YAML.load(File.read("examples/splitfx.sample.yml"))
    sfx = DTAS::SplitFX.new
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        guitar_pluck("foo.flac")
        sfx.import(hash, {})
        opts = { jobs: nil, silent: true }

        # ensure default FLAC target works
        WAIT_ALL_MTX.synchronize do
          tmp_err('err.txt') { sfx.run("flac", opts) }
        end
        expect = %w(1.flac 2.flac foo.flac)
        assert_equal expect, Dir["*.flac"].sort

        # compare results with expected output
        res_cmd = "sox 1.flac 2.flac -ts32 -c2 -r44100 result.s32 stats"
        res_pid = spawn(res_cmd, err: 'b.txt')
        exp_cmd = "sox foo.flac -ts32 -c2 -r44100 expect.s32 trim 4 stats"
        exp_pid = spawn(exp_cmd, err: 'a.txt')
        _, s = Process.waitpid2(res_pid)
        assert s.success?, "#{res_cmd}: #{s.inspect}"
        _, s = Process.waitpid2(exp_pid)
        assert s.success?, "#{exp_cmd}: #{s.inspect}"
        assert_equal File.read('a.txt'), File.read('b.txt')

        assert_contains_stats('err.txt')

        cmp = "cmp result.s32 expect.s32"
        assert system(cmp), cmp

        # try Ogg Opus, use opusenc/opusdec for now since that's available
        # in Debian 7.0 (sox.git currently has opusfile support, but that
        # hasn't made it into Debian, yet)
        if `which opusenc 2>/dev/null`.size > 0 &&
           `which opusdec 2>/dev/null`.size > 0
          WAIT_ALL_MTX.synchronize do
            tmp_err('opus.err.txt') { sfx.run("opusenc", opts) }
          end
          assert_contains_stats('opus.err.txt')

          # ensure opus lengths match flac ones, we decode using opusdec
          # since sox does not yet have opus support in Debian 7.0
          %w(1 2).each do |nr|
            cmd = "opusdec #{nr}.opus #{nr}.wav 2>/dev/null"
            assert system(cmd), cmd
            assert_equal `soxi -D #{nr}.flac`, `soxi -D #{nr}.wav`
          end

          # ensure 16/44.1kHz FLAC works (CDDA-like)
          File.unlink('1.flac', '2.flac')
          WAIT_ALL_MTX.synchronize do
            tmp_err('flac-cdda.err.txt') { sfx.run("flac-cdda", opts) }
          end
          assert_contains_stats('flac-cdda.err.txt')
          %w(1 2).each do |nr|
            assert_equal `soxi -D #{nr}.flac`, `soxi -D #{nr}.wav`
          end
        end
      end
    end
  end
end

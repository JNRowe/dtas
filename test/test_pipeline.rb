# Copyright (C) 2017-2019 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'dtas/pipeline'

class TestPipeline < Testcase
  include DTAS::Pipeline
  def setup
    @env = ENV.to_hash
  end

  def pipeline_result
    IO.pipe do |rd, wr|
      begin
        pid = fork do
          rd.close
          $stdout.reopen(wr)
          yield
          exit!(0)
        end
        wr.close
        return rd.read
      ensure
        _, status = Process.waitpid2(pid)
        assert_predicate status, :success?
      end
    end
    nil
  end

  def test_pipeline
    assert_equal("BYYRU\n", pipeline_result do
      run_pipeline(@env, [
        %w(echo hello), # anything which generates something to stdout
        %w(tr [a-z] [A-Z]), # upcase
        # this lambda runs inside its own process
        lambda do
          $stdin.each_line { |l| $stdout.write("#{l.chomp.reverse}\n") }
          exit!(0)
        end,
        # rot13
        %w(tr [a-m][n-z][A-M][N-Z] [n-z][a-m][N-Z][A-M])
      ])
    end)
  end
end

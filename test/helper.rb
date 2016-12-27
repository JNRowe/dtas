# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
$stdout.sync = $stderr.sync = Thread.abort_on_exception = true
require 'thread'
WAIT_ALL_MTX = Mutex.new

# fork-aware coverage data gatherer, see also test/covshow.rb
if ENV["COVERAGE"]
  require "coverage"
  COVMATCH = %r{/lib/dtas\b.*rb\z}
  COVTMP = File.open("coverage.dump", IO::CREAT|IO::RDWR)
  COVTMP.binmode
  COVTMP.sync = true

  def __covmerge
    res = Coverage.result

    # we own this file (at least until somebody tries to use NFS :x)
    COVTMP.flock(File::LOCK_EX)

    COVTMP.rewind
    prev = COVTMP.read
    prev = prev.empty? ? {} : Marshal.load(prev)
    res.each do |filename, counts|
      # filter out stuff that's not in our project
      COVMATCH =~ filename or next

      # For compatibility with https://bugs.ruby-lang.org/issues/9508
      # TODO: support those features if that gets merged into mainline
      unless Array === counts
        counts = counts[:lines]
      end

      merge = prev[filename] || []
      merge = merge
      counts.each_with_index do |count, i|
        count or next
        merge[i] = (merge[i] || 0) + count
      end
      prev[filename] = merge
    end
    COVTMP.rewind
    COVTMP.truncate(0)
    COVTMP.write(Marshal.dump(prev))
  ensure
    COVTMP.flock(File::LOCK_UN)
  end

  Coverage.start
  at_exit { __covmerge }
end

begin
  gem 'minitest'
rescue LoadError
end
require 'minitest/autorun'
require "tempfile"

Testcase = begin
  Minitest::Test
rescue NameError
  begin
    Minitest::Unit::TestCase # minitest 4
  rescue
    MiniTest::Unit::TestCase # minitest 3
  end
end

FIFOS = []
def tmpfifo
  tmp = Tempfile.new(%w(dtas-test .fifo))
  path = tmp.path
  tmp.close!
  assert system(*%W(mkfifo #{path})), "mkfifo #{path}"

  if FIFOS.empty?
    at_exit do
      FIFOS.each { |(pid,_path)| File.unlink(_path) if $$ == pid }
    end
  end
  FIFOS << [ $$, path ]
  path
end

require 'tmpdir'
class Dir
  require 'fileutils'
  def Dir.mktmpdir
    begin
      d = "#{Dir.tmpdir}/#$$.#{rand}"
      Dir.mkdir(d)
    rescue Errno::EEXIST
    end while true
    begin
      yield d
    ensure
      FileUtils.remove_entry(d)
    end
  end
end unless Dir.respond_to?(:mktmpdir)

def guitar_pluck(outfile)
  outfile =~ %r{\A[\w\./-]+\z} or raise ArgumentError, "bad chars"
  cmd = '(for n in E2 A2 D3 G3 B3 E4; do '\
         'sox -n -ts32 -c2 -r44100 - synth 4 pluck $n; done ) | ' \
         "sox -ts32 -c2 -r44100 - #{outfile}"
  assert_equal(true, system(cmd), cmd)
end

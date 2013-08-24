# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
$stdout.sync = $stderr.sync = Thread.abort_on_exception = true

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

gem 'minitest'
require 'minitest/autorun'
require "tempfile"

FIFOS = []
at_exit { FIFOS.each { |(pid,path)| File.unlink(path) if $$ == pid } }
def tmpfifo
  tmp = Tempfile.new(%w(dtas-test .fifo))
  path = tmp.path
  tmp.close!
  assert system(*%W(mkfifo #{path})), "mkfifo #{path}"
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

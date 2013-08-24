# -*- encoding: binary -*-
# :stopdoc:
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'

# parses lines from play(1) -S/--show-progress like this:
#  In:0.00% 00:00:37.34 [00:00:00.00] Out:1.65M [ -====|====  ]        Clip:0
#
# The authors of sox probably did not intend for the output of play(1) to
# be parsed, but we do it anyways.  We need to be ready to update this
# code in case play(1) output changes.
# play -S/--show-progress
class DTAS::SinkReaderPlay
  attr_reader :time, :out, :meter, :clips, :headroom
  attr_reader :to_io
  attr_reader :wr # this is stderr of play(1)

  def initialize
    @to_io, @wr = IO.pipe
    reset
  end

  def readable_iter
    buf = Thread.current[:dtas_lbuf] ||= ""
    begin
      @rbuf << @to_io.read_nonblock(1024, buf)

      # do not OOM in case SoX changes output format on us
      @rbuf.clear if @rbuf.size > 0x10000

      # don't handle partial read
      next unless / Clip:\S+ *\z/ =~ @rbuf

      if @rbuf.gsub!(/(.*)\rIn:\S+ (\S+) \S+ Out:(\S+)\s+(\[[^\]]+\]) /m, "")
        err = $1
        @time = $2
        @out = $3
        @meter = $4
        if @rbuf.gsub!(/Hd:(\d+\.\d+) Clip:(\S+) */, "")
          @headroom = $1
          @clips = $2
        elsif @rbuf.gsub!(/\s+Clip:(\S+) */, "")
          @headroom = nil
          @clips = $1
        end

        $stderr.write(err)
      end
    rescue EOFError
      return nil
    rescue Errno::EAGAIN
      return :wait_readable
    end while true
  end

  def close
    @wr.close unless @wr.closed?
    @to_io.close
  end

  def reset
    @rbuf = ""
    @time = @out = @meter = @headroom = @clips = nil
  end

  def closed?
    @to_io.closed?
  end
end

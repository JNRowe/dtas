# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)

# used in various places for safe wakeups from IO.select via signals
# A fallback for non-Linux systems lacking the "sleepy_penguin" RubyGem
require_relative 'nonblock'
class DTAS::Sigevent # :nodoc:
  attr_reader :to_io

  def initialize
    @to_io, @wr = DTAS::Nonblock.pipe
    @rbuf = ''
  end

  def signal
    @wr.syswrite('.') rescue nil
  end

  def readable_iter
    case @to_io.read_nonblock(11, @rbuf, exception: false)
    when :wait_readable then return :wait_readable
    else
      yield self, nil # calls DTAS::Process.reaper
    end while true
  end

  def close
    @to_io.close
    @wr.close
  end
end

# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true

# used in various places for safe wakeups from IO.select via signals
# A fallback for non-Linux systems lacking the "splice" syscall
require_relative '../nonblock'
class DTAS::Sigevent # :nodoc:
  attr_reader :to_io

  def initialize
    @to_io, @wr = DTAS::Nonblock.pipe
    @rbuf = ''.b
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

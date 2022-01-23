# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true

# used in various places for safe wakeups from IO.select via signals
# This requires a modern GNU/Linux system with eventfd(2) support
require 'fiddle'
class DTAS::Sigevent # :nodoc:

  EventFD = Fiddle::Function.new(DTAS.libc['eventfd'],
    [ Fiddle::TYPE_INT, Fiddle::TYPE_INT ], # initval, flags
    Fiddle::TYPE_INT) # fd

  attr_reader :to_io
  ONE = -([ 1 ].pack('Q'))

  def initialize
    fd = EventFD.call(0, 02000000|00004000) # EFD_CLOEXEC|EFD_NONBLOCK
    raise "eventfd failed: #{Fiddle.last_error}" if fd < 0
    @to_io = IO.for_fd(fd)
    @buf = ''.b
  end

  def signal
    @to_io.syswrite(ONE)
  end

  def readable_iter
    @to_io.read_nonblock(8, @buf, exception: false)
    yield self, nil # calls DTAS::Process.reaper
    :wait_readable
  end

  def close
    @to_io.close
  end
end

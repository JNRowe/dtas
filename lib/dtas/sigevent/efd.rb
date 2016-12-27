# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>

# used in various places for safe wakeups from IO.select via signals
# This requires a modern Linux system and the "sleepy_penguin" RubyGem
class DTAS::Sigevent < SleepyPenguin::EventFD # :nodoc:
  def self.new
    super(0, :CLOEXEC)
  end

  def signal
    incr(1)
  end

  def readable_iter
    value(true)
    yield self, nil # calls DTAS::Process.reaper
    :wait_readable
  end
end

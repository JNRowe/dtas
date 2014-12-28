# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
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

# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
class DTAS::Sigevent < SleepyPenguin::EventFD # :nodoc:
  include SleepyPenguin

  def self.new
    super(0, EventFD::CLOEXEC)
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

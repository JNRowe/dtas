# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
module DTAS # :nodoc:
  # try to use the monotonic clock in Ruby >= 2.1, it is immune to clock
  # offset adjustments and generates less garbage (Float vs Time object)
  begin
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    def self.now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  rescue NameError, NoMethodError
    def self.now # Ruby <= 2.0
      Time.now.to_f
    end
  end
end

require_relative 'dtas/compat_onenine'
require_relative 'dtas/spawn_fix'

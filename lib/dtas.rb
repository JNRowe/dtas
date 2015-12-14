# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)

# DTAS currently exposes no public API for Ruby programmers.
# See http://dtas.80x24.org/ for more info.
module DTAS

  # try to use the monotonic clock in Ruby >= 2.1, it is immune to clock
  # offset adjustments and generates less garbage (Float vs Time object)
  # :stopdoc:
  begin
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    def self.now # :nodoc:
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  rescue NameError, NoMethodError
    def self.now # :nodoc:
      Time.now.to_f # Ruby <= 2.0
    end
  end

  @null = nil
  def self.null # :nodoc:
    @null ||= File.open('/dev/null', 'r+')
  end
  # :startdoc:
end

require_relative 'dtas/compat_onenine'
require_relative 'dtas/spawn_fix'

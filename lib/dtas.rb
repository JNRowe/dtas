# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true

# DTAS currently exposes no public API for Ruby programmers.
# See https://80x24.org/dtas.git/about/ for more info.
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

  @libc = nil
  def self.libc
    @libc ||= begin
      require 'fiddle'
      Fiddle.dlopen(nil)
    end
  end

  # String#-@ will deduplicate strings when Ruby 2.5 is released (Dec 2017)
  # https://bugs.ruby-lang.org/issues/13077
  if RUBY_VERSION.to_f >= 2.5
    def self.dedupe_str(str)
      -str
    end
  else
    # Ruby 2.1 - 2.4, noop for older Rubies
    def self.dedupe_str(str)
      eval "#{str.inspect}.freeze"
    end
  end
  # :startdoc:
end

require_relative 'dtas/compat_onenine'
require_relative 'dtas/spawn_fix'
require_relative 'dtas/encoding'
DTAS.extend(DTAS::Encoding)

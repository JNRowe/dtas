# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true

# DTAS currently exposes no public API for Ruby programmers.
# See https://80x24.org/dtas.git/about/ for more info.
module DTAS

  # try to use the monotonic clock in Ruby >= 2.1, it is immune to clock
  # offset adjustments and generates less garbage (Float vs Time object)
  # :stopdoc:
  def self.now # :nodoc:
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
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

  # prevent breakage in Psych 4.x; we're a shell and designed to execute code
  def self.yaml_load(buf)
    require 'yaml'
    YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(buf) : YAML.load(buf)
  end
  # :startdoc:
end

require_relative 'dtas/encoding'
DTAS.extend(DTAS::Encoding)

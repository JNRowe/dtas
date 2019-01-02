# Copyright (C) 2013-2019 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
begin
  require 'sleepy_penguin'
rescue LoadError
end
require_relative '../dtas'
require_relative 'writable_iter'
require_relative 'nonblock'

# pipe wrapper for -player sinks
class DTAS::Pipe < DTAS::Nonblock # :nodoc:
  include DTAS::WritableIter
  attr_accessor :sink

  def self.new
    _, w = rv = pipe
    w.writable_iter_init
    rv
  end

  def pipe_size=(nr)
    defined?(SleepyPenguin::F_SETPIPE_SZ) and
      fcntl(SleepyPenguin::F_SETPIPE_SZ, nr)
  end

  def pipe_size
    fcntl(SleepyPenguin::F_GETPIPE_SZ)
  end if defined?(SleepyPenguin::F_GETPIPE_SZ)

  # avoid syscall, we never change IO#nonblock= directly
  def nonblock?
    false
  end
end

# for non-blocking sinks, this avoids extra fcntl(..., F_GETFL) syscalls
# We don't need fcntl at all for splice/tee in Linux
# For non-Linux, we write_nonblock/read_nonblock already call fcntl()
# behind our backs, so there's no need to repeat it.
class DTAS::PipeNB < DTAS::Pipe # :nodoc:
  def nonblock?
    true
  end
end

# Copyright (C) 2013-2019 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'
require_relative 'writable_iter'
require_relative 'nonblock'

# pipe wrapper for -player sinks
class DTAS::Pipe < DTAS::Nonblock # :nodoc:
  include DTAS::WritableIter
  attr_accessor :sink

  if RUBY_PLATFORM =~ /linux/i && File.readable?('/proc/sys/fs/pipe-max-size')
    F_SETPIPE_SZ = 1031
    F_GETPIPE_SZ = 1032
  end

  def self.new
    _, w = rv = pipe
    w.writable_iter_init
    rv
  end

  def pipe_size=(nr)
    fcntl(F_SETPIPE_SZ, nr) if defined?(F_SETPIPE_SZ)
  rescue Errno::EINVAL # old kernel
  rescue Errno::EPERM
    # resizes fail if Linux is close to the pipe limit for the user
    # or if the user does not have permissions to resize
  end

  def pipe_size
    fcntl(F_GETPIPE_SZ)
  end if defined?(F_GETPIPE_SZ)

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

# -*- encoding: binary -*-
# :stopdoc:
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
begin
  require 'io/splice'
rescue LoadError
end
require_relative '../dtas'
require_relative 'writable_iter'

class DTAS::Pipe < IO
  include DTAS::WritableIter
  attr_accessor :sink

  def self.new
    _, w = rv = pipe
    w.writable_iter_init
    rv
  end

  # create no-op methods for non-Linux
  unless method_defined?(:pipe_size=)
    def pipe_size=(_)
    end

    def pipe_size
    end
  end
end

# for non-blocking sinks, this avoids extra fcntl(..., F_GETFL) syscalls
# We don't need fcntl at all for splice/tee in Linux
# For non-Linux, we write_nonblock/read_nonblock already call fcntl()
# behind our backs, so there's no need to repeat it.
class DTAS::PipeNB < DTAS::Pipe
  def nonblock?
    true
  end
end

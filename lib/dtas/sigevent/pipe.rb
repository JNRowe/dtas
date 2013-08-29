# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
class DTAS::Sigevent # :nodoc:
  attr_reader :to_io

  def initialize
    @to_io, @wr = IO.pipe
  end

  def signal
    @wr.syswrite('.') rescue nil
  end

  def readable_iter
    begin
      @to_io.read_nonblock(11)
      yield self, nil # calls DTAS::Process.reaper
    rescue Errno::EAGAIN
      return :wait_readable
    end while true
  end

  def close
    @to_io.close
    @wr.close
  end
end

# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)

class DTAS::Nonblock < IO
  if RUBY_VERSION.to_f <= 2.0
    EX = {}.freeze
    def read_nonblock(len, buf = nil, opts = EX)
      super(len, buf)
    rescue IO::WaitReadable
      raise if opts[:exception]
      :wait_readable
    rescue EOFError
      raise if opts[:exception]
      nil
    end

    def write_nonblock(buf, opts = EX)
      super(buf)
    rescue IO::WaitWritable
      raise if opts[:exception]
      :wait_writable
    end
  end
end

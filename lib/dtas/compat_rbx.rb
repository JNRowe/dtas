# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)

# ref: https://github.com/rubysl/rubysl-io-wait/issues/1
# this ignores buffers and is Linux-only
class IO
  def nread
    buf = "\0" * 8
    ioctl(0x541B, buf)
    buf.unpack("l_")[0]
  end
end if ! IO.method_defined?(:nread) && RUBY_PLATFORM =~ /linux/

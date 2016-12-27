# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
module DTAS::Source::Common # :nodoc:
  attr_reader :dst_zero_byte # first byte this source object saw
  attr_reader :dst
  attr_accessor :requeued

  # buf - a DTAS::Buffer object (pipe)
  def dst_assoc(buf)
    @dst = buf
    @dst_zero_byte = buf.bytes_xfer + buf.inflight
    @requeued = false
  end
end

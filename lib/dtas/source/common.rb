# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
module DTAS::Source::Common # :nodoc:
  attr_reader :dst_zero_byte
  attr_reader :dst
  attr_accessor :requeued

  def dst_assoc(buf)
    @dst = buf
    @dst_zero_byte = buf.bytes_xfer + buf.inflight
    @requeued = false
  end
end

# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'

# used to manage writable state for -player pipes
module DTAS::WritableIter # :nodoc:
  attr_accessor :on_writable
  # we may use the ready_write flag to avoid an extra IO.select
  attr_accessor :ready_write

  def writable_iter_init
    @mark_writable = proc { @ready_write = true }
    @on_writable = nil
    @ready_write = true
  end

  def ready_write_optimized?
    rv = @ready_write
    @ready_write = false
    rv
  end

  def wait_writable_prepare
    @ready_write = false
    @on_writable ||= @mark_writable
  end

  # this is used to exchange our own writable status for the readable
  # status of the DTAS::Buffer which triggered us.
  def writable_iter
    if owr = @on_writable
      @on_writable = nil
      @ready_write = true
      owr.call # this triggers readability watching of DTAS::Buffer
    end
    :ignore
  end
end

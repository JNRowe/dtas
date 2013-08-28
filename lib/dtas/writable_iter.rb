# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'

module DTAS::WritableIter # :nodoc:
  attr_accessor :on_writable

  def writable_iter_init
    @on_writable = nil
  end

  # this is used to exchange our own writable status for the readable
  # status of the DTAS::Buffer which triggered us.
  def writable_iter
    if owr = @on_writable
      @on_writable = nil
      owr.call # this triggers readability watching of DTAS::Buffer
    end
    :ignore
  end
end

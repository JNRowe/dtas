# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'
require 'shellwords'

# We always escape binary strings because paths on POSIX filesystems are
# encoding agnostic.  Shellwords.split does give UTF-8 strings, but nothing
# cares at that point if the encoding isn't valid (and it's right to not care,
# again, filesystems can use any byte value in names except '\0'.
module DTAS::XS # :nodoc:
  def xs(ary)
    Shellwords.join(Array(ary).map(&:b))
  end
end

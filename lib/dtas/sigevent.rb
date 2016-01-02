# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
begin
  raise LoadError, "no eventfd with _DTAS_POSIX" if ENV["_DTAS_POSIX"]
  require 'sleepy_penguin'
  require_relative 'sigevent/efd'
rescue LoadError
  require_relative 'sigevent/pipe'
end

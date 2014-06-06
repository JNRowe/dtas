# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
begin
  raise LoadError, "no eventfd with _DTAS_POSIX" if ENV["_DTAS_POSIX"]
  require 'sleepy_penguin'
  require_relative 'sigevent/efd'
rescue LoadError
  require_relative 'sigevent/pipe'
end

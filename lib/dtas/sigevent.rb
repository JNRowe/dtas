# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
begin
  raise LoadError, "no eventfd with _DTAS_POSIX" if ENV["_DTAS_POSIX"]
  begin
    require_relative 'sigevent/efd'
  rescue LoadError
    require_relative 'sigevent/fiddle_efd'
  end
rescue LoadError
  require_relative 'sigevent/pipe'
end

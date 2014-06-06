# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
module DTAS::Serialize # :nodoc:
  def ivars_to_hash(ivars, rv = {})
    ivars.each { |k| rv[k] = instance_variable_get("@#{k}") }
    rv
  end
end

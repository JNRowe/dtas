# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
module DTAS::Serialize # :nodoc:
  def ivars_to_hash(ivars, rv = {})
    ivars.each { |k| rv[k] = instance_variable_get("@#{k}") }
    rv
  end
end

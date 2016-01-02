# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

# used to serialize player state to the state file
module DTAS::Serialize # :nodoc:
  def ivars_to_hash(ivars, rv = {})
    ivars.each { |k| rv[k] = instance_variable_get("@#{k}") }
    rv
  end
end

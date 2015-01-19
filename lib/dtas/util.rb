# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'

# in case we need to convert DB values to a linear scale
module DTAS::Util # :nodoc:
  def db_to_linear(val)
    Math.exp(val * Math.log(10) * 0.05)
  end

  def linear_to_db(val)
    Math.log10(val) * 20
  end
end

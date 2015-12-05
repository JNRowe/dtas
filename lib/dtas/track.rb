# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'

class DTAS::Track
  attr_reader :track_id
  attr_reader :to_path

  def initialize(track_id, path)
    @track_id = track_id
    @to_path = path
  end
end

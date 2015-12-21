# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative '../dtas'

class DTAS::Track # :nodoc:
  attr_reader :track_id
  attr_reader :to_path

  def initialize(track_id, path)
    @track_id = track_id
    @to_path = path
  end
end

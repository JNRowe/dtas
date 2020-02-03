# Copyright (C) 2018-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require './test/helper'
require 'dtas'
require 'yaml'

class TestEncoding < Testcase
  def test_encoding
    data = <<EOD # <20180111114546.77906b35@cumparsita.ch>
---
comments:
  ARTIST: !binary |-
    RW5yaXF1ZSBSb2Ryw61ndWV6
EOD
    hash = YAML.load(data)
    artist = DTAS.try_enc(hash['comments']['ARTIST'], Encoding::UTF_8)
    assert_equal 'Enrique Rodríguez', artist
  end
end

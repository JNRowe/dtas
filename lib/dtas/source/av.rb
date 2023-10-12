# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../../dtas'
require_relative 'av_ff_common'

# this is usually one input file
class DTAS::Source::Av # :nodoc:
  include DTAS::Source::AvFfCommon

  AV_DEFAULTS = COMMAND_DEFAULTS.merge(
    "command" =>
      'avconv -v error $SSPOS $PROBE -i "$INFILE" $AMAP -f sox - |' \
      'sox -p $SOXFMT - $TRIMFX $RGFX',

    "tryorder" => 2,
  )

  def initialize
    command_init(AV_DEFAULTS)
    @av_ff_probe = "avprobe"
  end

  def source_defaults
    AV_DEFAULTS
  end
end

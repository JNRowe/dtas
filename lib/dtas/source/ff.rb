# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../../dtas'
require_relative 'av_ff_common'

# ffmpeg support
# note: only tested with the compatibility wrapper in the Debian 7.0 package
# (so still using avconv/avprobe)
class DTAS::Source::Ff  # :nodoc:
  include DTAS::Source::AvFfCommon

  FF_DEFAULTS = COMMAND_DEFAULTS.merge(
    "command" =>
      'ffmpeg -v error $SSPOS $PROBE -i "$INFILE" $AMAP -f sox - |' \
      'sox -p $SOXFMT - $TRIMFX $RGFX',

    # I haven't tested this much since av is in Debian stable and ff is not
    "tryorder" => 2,
  )

  def initialize
    command_init(FF_DEFAULTS)
    @av_ff_probe = "ffprobe"
  end

  def source_defaults
    FF_DEFAULTS
  end
end

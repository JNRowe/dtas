# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../../dtas'
require_relative 'av_ff_common'

# this is usually one input file
class DTAS::Source::Av # :nodoc:
  include DTAS::Source::AvFfCommon

  AV_DEFAULTS = COMMAND_DEFAULTS.merge(
    "command" =>
      'avconv -v error $SSPOS $PROBE -i "$INFILE" $AMAP -f sox - |' \
      'sox -p $SOXFMT - $RGFX',

    # this is above ffmpeg because this av is the Debian default and
    # it's easier for me to test av than ff
    "tryorder" => 1,
  )

  def initialize
    command_init(AV_DEFAULTS)
    @av_ff_probe = "avprobe"
  end

  def source_defaults
    AV_DEFAULTS
  end
end

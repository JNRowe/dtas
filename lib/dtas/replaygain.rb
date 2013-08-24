# -*- encoding: binary -*-
# :stopdoc:
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
#
# Represents ReplayGain metadata for a DTAS::Source
# cleanup/validate values to prevent malicious files from making us
# run arbitrary commands
# *_peak values are 0..inf (1.0 being full scale, but >1 is possible
# *_gain values are specified in dB

class DTAS::ReplayGain
  ATTRS = %w(reference_loudness track_gain album_gain track_peak album_peak)
  ATTRS.each { |a| attr_reader a }

  def check_gain(val)
    /([+-]?\d+(?:\.\d+)?)/ =~ val ? $1 : nil
  end

  def check_float(val)
    /(\d+(?:\.\d+)?)/ =~ val ? $1 : nil
  end

  def initialize(comments)
    comments or return

    # the replaygain standard specifies 89.0 dB, but maybe some apps are
    # different...
    @reference_loudness =
              check_gain(comments["REPLAYGAIN_REFERENCE_LOUDNESS"]) || "89.0"

    @track_gain = check_gain(comments["REPLAYGAIN_TRACK_GAIN"])
    @album_gain = check_gain(comments["REPLAYGAIN_ALBUM_GAIN"])
    @track_peak = check_float(comments["REPLAYGAIN_TRACK_PEAK"])
    @album_peak = check_float(comments["REPLAYGAIN_ALBUM_PEAK"])
  end

  def self.new(comments)
    tmp = super
    tmp.track_gain ? tmp : nil
  end
end

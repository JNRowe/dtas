# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true

# Represents ReplayGain metadata for a DTAS::Source, only used by -player
# cleanup/validate values to prevent malicious files from making us
# run arbitrary commands
# *_peak values are 0..inf (1.0 being full scale, but >1 is possible
# *_gain values are specified in dB

class DTAS::ReplayGain # :nodoc:
  ATTRS = %w(reference_loudness track_gain album_gain track_peak album_peak)
  ENV_ATTRS = {}
  ATTRS.each do |a|
    attr_reader a
    ENV_ATTRS["REPLAYGAIN_#{a.upcase}"] = a
  end

  def check_gain(val)
    /([+-]?\d+(?:\.\d+)?)/ =~ val ? $1 : nil
  end

  def check_float(val)
    /(\d+(?:\.\d+)?)/ =~ val ? $1 : nil
  end

  # note: this strips the "dB" suffix, but that should be easier for apps
  # to deal with anyways...
  def to_env
    rv = {}
    # this will cause nil to be set if some envs are missing, this causes
    # Process.spawn to unset the environment if it was previously set
    # (leaked from some other process)
    ENV_ATTRS.each do |env_name, attr_name|
      rv[env_name] = __send__(attr_name)
    end
    rv
  end

  def initialize(comments)
    comments or return

    # the ReplayGain standard specifies 89.0 dB, but maybe some apps are
    # different...
    @reference_loudness = check_gain(comments["REPLAYGAIN_REFERENCE_LOUDNESS"])

    @track_gain = check_gain(comments["REPLAYGAIN_TRACK_GAIN"])
    @album_gain = check_gain(comments["REPLAYGAIN_ALBUM_GAIN"])
    @track_peak = check_float(comments["REPLAYGAIN_TRACK_PEAK"])
    @album_peak = check_float(comments["REPLAYGAIN_ALBUM_PEAK"])
  end

  def self.new(comments, field)
    tmp = super(comments)
    tmp.__send__(field) ? tmp : nil
  end
end

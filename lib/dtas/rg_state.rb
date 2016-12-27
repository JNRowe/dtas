# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
#
# provides support for generating appropriate effects for ReplayGain
# MAYBE: account for non-standard reference loudness (89.0 dB is standard)
require_relative '../dtas'
require_relative 'serialize'
require_relative 'util'
class DTAS::RGState # :nodoc:
  include DTAS::Serialize
  include DTAS::Util

  RG_MODE = {
    # attribute name => method to use
    "album_gain" => :rg_vol_gain,
    "track_gain" => :rg_vol_gain,
    "album_peak" => :rg_vol_norm,
    "track_peak" => :rg_vol_norm,
  }

  RG_DEFAULT = {
    "volume" => 1.0,
    # skip the effect if the adjustment is too small to be noticeable
    "gain_threshold" => 0.00000001, # in dB
    "norm_threshold" => 0.00000001,

    "preamp" => 0, # no extra adjustment
    # "mode" => "album_gain", # nil: off
    "mode" => nil, # nil: off
    "fallback_gain" => -6.0, # adjustment dB if necessary RG tag is missing
    "fallback_track" => true,
    "norm_level" => 1.0, # dBFS
  }

  SIVS = RG_DEFAULT.keys
  SIVS.each { |iv| attr_accessor iv }

  undef_method :volume=

  def volume=(val)
    val = 0 if val.to_i < 0
    @volume = val.round(4)
  end

  def initialize
    RG_DEFAULT.each do |k,v|
      instance_variable_set("@#{k}", v)
    end
  end

  def self.load(hash)
    rv = new
    hash.each { |k,v| rv.__send__("#{k}=", v) } if hash
    rv
  end

  def to_hash
    ivars_to_hash(SIVS)
  end

  def vol_db
    linear_to_db(@volume)
  end

  def to_hsh
    # no point in dumping default values, it's just a waste of space
    to_hash.delete_if { |k,v| RG_DEFAULT[k] == v }
  end

  def to_sox_gain(val)
    case val.infinite?
    when -1 then return 'gain -192'
    when 1 then return 'gain 192'
    else
      sprintf('gain %0.8g', val).freeze
    end
  end

  # returns a dB argument to the "gain" effect, nil if nothing found
  def rg_vol_gain(val)
    val = val.to_f + @preamp + vol_db
    return if val.abs < @gain_threshold
    to_sox_gain(val)
  end

  # returns a DB argument to the "gain" effect
  def rg_vol_norm(val)
    n = @norm_level == 1.0 ? @volume : @norm_level
    diff = n - val.to_f
    return if (n - diff).abs < @norm_threshold
    diff += n
    to_sox_gain(linear_to_db(diff))
  end

  # The ReplayGain fallback adjustment value (in dB), in case a file is
  # missing ReplayGain tags.  This is useful to avoid damage to speakers,
  # eardrums and amplifiers in case a file without then necessary ReplayGain
  # tag slips into the queue
  def rg_fallback_effect(reason)
    val = (@fallback_gain || 0) + @preamp + vol_db
    return if val.abs < @gain_threshold
    warn(reason) if $DEBUG
    to_sox_gain(val)
  end

  # returns an array (for command-line argument) for the effect needed
  # to apply ReplayGain
  # this may return nil
  def effect(source)
    unless @mode
      return @volume == 1.0 ? nil : to_sox_gain(vol_db)
    end
    rg = source.replaygain(@mode) or
      return rg_fallback_effect("ReplayGain tags missing for #@mode")
    val = rg.__send__(@mode)
    if ! val && @fallback_track && @mode =~ /\Aalbum_(\w+)/
      tag = "track_#$1"
      val = rg.__send__(tag) or
        return rg_fallback_effect("ReplayGain tag for #@mode missing")
      warn("tag for #@mode missing, using #{tag}")
    end
    # this may be nil if the adjustment is too small:
    __send__(RG_MODE[@mode], val)
  end
end

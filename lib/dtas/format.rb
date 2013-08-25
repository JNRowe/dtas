# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
# class represents an audio format (type/bits/channels/sample rate/...)
require_relative '../dtas'
require_relative 'process'
require_relative 'serialize'

class DTAS::Format # :nodoc:
  include DTAS::Process
  include DTAS::Serialize
  NATIVE_ENDIAN = [1].pack("l") == [1].pack("l>") ? "big" : "little"

  attr_accessor :type # s32, f32, f64 ... any point in others?
  attr_accessor :channels # 1..666
  attr_accessor :rate     # 44100, 48000, 88200, 96000, 176400, 192000 ...
  attr_accessor :bits # only set for playback on 16-bit DACs
  attr_accessor :endian

  FORMAT_DEFAULTS = {
    "type" => "s32",
    "channels" => 2,
    "rate" => 44100,
    "bits" => nil,   # default: implied from type
    "endian" => nil, # unspecified
  }
  SIVS = FORMAT_DEFAULTS.keys

  def self.load(hash)
    fmt = new
    return fmt unless hash
    (SIVS & hash.keys).each do |k|
      fmt.instance_variable_set("@#{k}", hash[k])
    end
    fmt
  end

  def initialize
    FORMAT_DEFAULTS.each do |k,v|
      instance_variable_set("@#{k}", v)
    end
  end

  def to_sox_arg
   rv = %W(-t#@type -c#@channels -r#@rate)
   rv.concat(%W(-b#@bits)) if @bits # needed for play(1) to 16-bit DACs
   rv
  end

  # returns 'be' or 'le' depending on endianess
  def endian2
    case e = @endian || NATIVE_ENDIAN
    when "big"
      "be"
    when "little"
      "le"
    else
      raise"unsupported endian=#{e}"
    end
  end

  def to_eca_arg
    %W(-f #{@type}_#{endian2},#@channels,#@rate)
  end

  def inspect
    "<#{self.class}(#{xs(to_sox_arg)})>"
  end

  def to_hsh
    to_hash.delete_if { |k,v| v == FORMAT_DEFAULTS[k] }
  end

  def to_hash
    ivars_to_hash(SIVS)
  end

  # for the _decoded_ output
  def bits_per_sample
    return @bits if @bits
    /\A[fst](8|16|24|32|64)\z/ =~ @type or
      raise TypeError, "invalid type=#@type (must be s32/f32/f64)"
    $1.to_i
  end

  def bytes_per_sample
    bits_per_sample / 8
  end

  def to_env
    rv = {
      "SOX_FILETYPE" => @type,
      "CHANNELS" => @channels.to_s,
      "RATE" => @rate.to_s,
      "ENDIAN" => @endian || NATIVE_ENDIAN,
      "SOXFMT" => to_sox_arg.join(' '),
      "ECAFMT" => to_eca_arg.join(' '),
      "ENDIAN2" => endian2,
    }
    begin # don't set these if we can't get them, SOX_FILETYPE may be enough
      rv["BITS_PER_SAMPLE"] = bits_per_sample.to_s
    rescue TypeError
    end
    rv
  end

  def bytes_to_samples(bytes)
    bytes / bytes_per_sample / @channels
  end

  def bytes_to_time(bytes)
    Time.at(bytes_to_samples(bytes) / @rate.to_f)
  end

  def valid_type?(type)
    !!(type =~ %r{\A[us](?:8|16|24|32)\z} || type =~ %r{\Af?:(32|64)})
  end

  def valid_endian?(endian)
    !!(endian =~ %r{\A(?:big|little|swap)\z})
  end

  # HH:MM:SS.frac (don't bother with more complex times, too much code)
  # part of me wants to drop this feature from playq, feels like bloat...
  def hhmmss_to_samples(hhmmss)
    time = hhmmss.dup
    rv = 0
    if time.sub!(/\.(\d+)\z/, "")
      # convert fractional second to sample count:
      rv = ("0.#$1".to_f * @rate).to_i
    end

    # deal with HH:MM:SS
    t = time.split(/:/)
    raise ArgumentError, "Bad time format: #{hhmmss}" if t.size > 3

    mult = 1
    while part = t.pop
      rv += part.to_i * mult * @rate
      mult *= 60
    end
    rv
  end
end

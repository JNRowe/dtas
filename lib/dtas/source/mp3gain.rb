# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../process'

module DTAS::Source::Mp3gain # :nodoc:
  include DTAS::Process
  # we use dBFS = 1.0 as scale (not 32768)
  def __mp3gain_peak(str)
    sprintf("%0.8g", str.to_f / 32768.0)
  end

  # massage mp3gain(1) output
  def mp3gain_comments
    tmp = {}
    case @infile
    when String
      @infile =~ /\.mp[g23]\z/in or return
      qx(%W(mp3gain -s c #@infile)).split("\n").each do |line|
        case line
        when /^Recommended "(Track|Album)" dB change:\s*(\S+)/
          tmp["REPLAYGAIN_#{$1.upcase}_GAIN"] = $2
        when /^Max PCM sample at current gain: (\S+)/
          tmp["REPLAYGAIN_TRACK_PEAK"] = __mp3gain_peak($1)
        when /^Max Album PCM sample at current gain: (\S+)/
          tmp["REPLAYGAIN_ALBUM_PEAK"] = __mp3gain_peak($1)
        end
      end
      tmp
    else
      raise TypeError, "unsupported type: #{@infile.inspect}"
    end
  rescue => e
    $DEBUG and
        warn("mp3gain(#{@infile.inspect}) failed: #{e.message} (#{e.class})")
  end
end

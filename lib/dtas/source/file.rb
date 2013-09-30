# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../../dtas'
require_relative '../source'
require_relative '../command'
require_relative '../format'
require_relative '../process'
require_relative '../cue_index'

module DTAS::Source::File # :nodoc:
  attr_reader :infile
  attr_reader :offset
  attr_accessor :tryorder
  require_relative 'common' # dtas/source/common
  require_relative 'mp3gain'
  include DTAS::Command
  include DTAS::Process
  include DTAS::Source::Common
  include DTAS::Source::Mp3gain

  FILE_SIVS = %w(infile comments command env) # for the "current" command
  SRC_SIVS = %w(command env tryorder)

  def source_file_dup(infile, offset)
    rv = dup
    rv.__file_init(infile, offset)
    rv
  end

  def __file_init(infile, offset)
    @env = @env.dup
    @format = nil
    @infile = infile
    @offset = offset
    @comments = nil
    @samples = nil
    @cuebp = nil
    @rg = nil
  end

  # this exists mainly to make the mpris interface easier, but it's not
  # necessary, the mpris interface also knows the sample rate
  def offset_us
    (offset_samples / format.rate.to_f) * 1000000
  end

  # returns any offset in samples (relative to the original source file),
  # likely zero unless seek was used
  def offset_samples
    return 0 unless @offset
    case @offset
    when /\A\d+s\z/
      @offset.to_i
    else
      format.hhmmss_to_samples(@offset)
    end
  end

  # A user may be downloading the file and start playing
  # it before the download completes, this refreshes
  def samples!
    @samples = nil
    samples
  end

  def comments
    @comments ||= __load_comments
  end

  def to_hash
    rv = ivars_to_hash(FILE_SIVS)
    rv["samples"] = samples
    rv
  end

  def replaygain
    @rg ||= DTAS::ReplayGain.new(comments) ||
            DTAS::ReplayGain.new(mp3gain_comments)
  end

  def to_source_cat
    ivars_to_hash(SRC_SIVS)
  end

  def load!(src_hsh)
    SRC_SIVS.each do |field|
      val = src_hsh[field] and instance_variable_set("@#{field}", val)
    end
  end

  def to_state_hash
    defaults = source_defaults # see dtas/source/{av,sox}.rb
    to_source_cat.delete_if { |k,v| v == defaults[k] }
  end

  def cuebreakpoints
    rv = @cuebp and return rv
    rv = []
    begin
      str = qx(@env, %W(metaflac --export-cuesheet-to=- #@infile))
    rescue
      return rv
    end
    str.scan(/^    INDEX (\d+) (\S+)/) do |m|
      index = m[0]
      time = m[1].dup
      case time
      when /\A\d+\z/
        time << "s" # sample count (flac 1.3.0)
      else # HH:MM:SS:FF
        # FF/75 CDDA frames per second, convert to fractional seconds
        time.sub!(/:(\d+)\z/, "")
        frames = $1.to_f
        if frames > 0
          time = sprintf("#{time}.%0.6g", frames / 75.0)
        end
      end
      rv << DTAS::CueIndex.new(index, time)
    end
    @cuebp = rv
  end
end

# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'serialize'

# this is inspired by the MPRIS 2.0 TrackList spec
class DTAS::Tracklist # :nodoc:
  include DTAS::Serialize
  attr_accessor :repeat # true, false, 1

  SIVS = %w(list pos repeat)
  TL_DEFAULTS = {
    "list" => [],
    "pos" => -1,
    "repeat" => false,
  }

  def self.load(hash)
    obj = new
    obj.instance_eval do
      list = hash["list"] and @list.replace(list)
      @pos = hash["pos"] || -1
      @repeat = hash["repeat"] || false
    end
    obj
  end

  def to_hsh
    ivars_to_hash(SIVS).delete_if { |k,v| TL_DEFAULTS[k] == v }
  end

  def initialize
    TL_DEFAULTS.each { |k,v| instance_variable_set("@#{k}", v) }
    @list = []
    @goto_off = @goto_pos = nil
  end

  def reset
    @goto_off = @goto_pos = nil
    @pos = TL_DEFAULTS["pos"]
  end

  def size
    @list.size
  end

  # caching this probably isn't worth it.  a tracklist is usually
  # a few tens of tracks, maybe a hundred at most.
  def _track_id_map
    by_track_id = {}
    @list.each_with_index { |t,i| by_track_id[t.object_id] = i }
    by_track_id
  end

  def get_tracks(track_ids)
    by_track_id = _track_id_map
    track_ids.map do |track_id|
      idx = by_track_id[track_id]
      # dtas-mpris fills in the metadata, we just return a path
      [ track_id, idx ? @list[idx] : nil ]
    end
  end

  def tracks
    @list.map { |t| t.object_id }
  end

  def advance_track(repeat_ok = true)
    return if @list.empty?
    # @repeat == 1 for single track repeat
    next_pos = @goto_pos || @pos + (@repeat == 1 ? 0 : 1)
    next_off = @goto_off # nil by default
    @goto_pos = @goto_off = nil
    if @list[next_pos]
      @pos = next_pos
    elsif @repeat && repeat_ok
      next_pos = @pos = 0
    else
      return
    end
    [ @list[next_pos], next_off ]
  end

  def cur_track
    @pos >= 0 ? @list[@pos] : nil
  end

  def add_track(track, after_track_id = nil, set_as_current = false)
    if after_track_id
      by_track_id = _track_id_map
      idx = by_track_id[after_track_id] or
        raise ArgumentError, "after_track_id invalid"
      @list[idx, 1] = [ @list[idx], track ]
      @pos = idx + 1 if set_as_current
    else # nil = first_track
      @list.unshift(track)
      @pos = 0 if set_as_current
    end
    track.object_id
  end

  def remove_track(track_id)
    by_track_id = _track_id_map
    if idx = by_track_id.delete(track_id)
      @list[idx] = nil
      @list.compact!
      # TODO: what do we do with @pos (and the currently-playing track)
    end
  end

  def go_to(track_id, offset_hhmmss = nil)
    by_track_id = _track_id_map
    if idx = by_track_id[track_id]
      @goto_off = offset_hhmmss
      return @list[@goto_pos = idx]
    end
    @goto_pos = nil
    # noop if track_id is invalid
  end

  def previous!
    return if @list.empty?
    prev_idx = @pos - 1
    if prev_idx < 0
      # stop playback if nothing to go back to.
      prev_idx = @repeat ? @list.size - 1 : @list.size
    end
    @goto_pos = prev_idx
  end
end
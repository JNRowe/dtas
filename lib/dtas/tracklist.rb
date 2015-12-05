# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'serialize'
require_relative 'track'

# the a tracklist object for -player
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
      list = hash["list"] and @list.replace(list.map! { |s| new_track(s) })
      @pos = hash["pos"] || -1
      @repeat = hash["repeat"] || false
    end
    obj
  end

  def to_hsh
    h = ivars_to_hash(SIVS)
    h.delete_if { |k,v| TL_DEFAULTS[k] == v }
    list = h['list'] and h['list'] = list.map(&:to_path)
    h
  end

  def initialize
    TL_DEFAULTS.each { |k,v| instance_variable_set("@#{k}", v) }
    @list = []
    @goto_off = @goto_pos = nil
    @track_nr = 0
  end

  def new_track(path)
    n = @track_nr += 1

    # nobody needs a billion tracks in their tracklist, right?
    # avoid promoting to Bignum on 32-bit
    @track_nr = n = 1 if n >= 0x3fffffff

    DTAS::Track.new(n, path)
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
    @list.each_with_index { |t,i| by_track_id[t.track_id] = i }
    by_track_id
  end

  def get_tracks(track_ids)
    by_track_id = _track_id_map
    track_ids.map do |track_id|
      idx = by_track_id[track_id]
      # dtas-mpris fills in the metadata, we just return a path
      [ track_id, idx ? @list[idx].to_path : nil ]
    end
  end

  def tracks
    @list.map(&:track_id)
  end

  def advance_track(repeat_ok = true)
    return if @list.empty?
    # @repeat == 1 for single track repeat
    repeat = repeat_ok ? @repeat : false
    next_pos = @goto_pos || @pos + (repeat == 1 ? 0 : 1)
    next_off = @goto_off # nil by default
    @goto_pos = @goto_off = nil
    if @list[next_pos]
      @pos = next_pos
    elsif repeat
      next_pos = @pos = 0
    else
      return
    end
    [ @list[next_pos].to_path, next_off ]
  end

  def cur_track
    @pos >= 0 ? @list[@pos] : nil
  end

  def add_track(track, after_track_id = nil, set_as_current = false)
    track = new_track(track)
    if after_track_id
      by_track_id = _track_id_map
      idx = by_track_id[after_track_id] or
        raise ArgumentError, "after_track_id invalid"
      @list[idx, 1] = [ @list[idx], track ]
      if set_as_current
        @pos = idx + 1
      else
        @pos += 1 if @pos > idx
      end
    else # nil = first_track
      @list.unshift(track)
      if set_as_current
        @pos = 0
      else
        @pos += 1 if @pos >= 0
      end
    end
    track.track_id
  end

  def remove_track(track_id)
    by_track_id = _track_id_map
    idx = by_track_id.delete(track_id) or return false
    track = @list.delete_at(idx)
    len = @list.size
    if @pos >= len
      @pos = len == 0 ? TL_DEFAULTS["pos"] : len
    end
    @goto_pos = @goto_pos = nil # TODO: reposition?
    track.to_path
  end

  def go_to(track_id, offset_hhmmss = nil)
    by_track_id = _track_id_map
    if idx = by_track_id[track_id]
      @goto_off = offset_hhmmss
      return @list[@goto_pos = idx].to_path
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

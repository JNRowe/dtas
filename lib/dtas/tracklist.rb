# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'serialize'

# this is inspired by the MPRIS 2.0 TrackList spec
class DTAS::Tracklist
  include DTAS::Serialize
  attr_accessor :repeat

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

  def next_track(repeat_ok = true)
    return if @list.empty?
    next_pos = @pos + 1
    if @list[next_pos]
      @pos = next_pos
    elsif @repeat && repeat_ok
      next_pos = @pos = 0
    else
      return
    end
    @list[next_pos]
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
  end

  def remove_track(track_id)
    by_track_id = _track_id_map
    if idx = by_track_id.delete(track_id)
      @list[idx] = nil
      @list.compact!
      # TODO: what do we do with @pos (and the currently-playing track)
    end
  end

  def go_to(track_id)
    by_track_id = _track_id_map
    if idx = by_track_id[track_id]
      return @list[@pos = idx]
    end
    # noop if track_id is invalid
  end
end

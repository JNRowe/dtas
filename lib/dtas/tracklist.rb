# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'
require_relative 'serialize'
require_relative 'track'

# the a tracklist object for -player
# this is inspired by the MPRIS 2.0 TrackList spec
class DTAS::Tracklist # :nodoc:
  include DTAS::Serialize
  attr_accessor :repeat # true, false, 1
  attr_reader :shuffle  # false or shuffled @list
  attr_accessor :max # integer
  attr_accessor :consume # boolean

  TL_DEFAULTS = {
    'pos' => -1,
    'repeat' => false,
    'max' => 20_000,
    'consume' => false,
  }
  SIVS = TL_DEFAULTS.keys

  def self.load(hash)
    obj = new
    obj.instance_eval do
      list = hash['list'] and @list.replace(list.map { |s| new_track(s) })
      SIVS.each do |k|
        instance_variable_set("@#{k}", hash[k] || TL_DEFAULTS[k])
      end

      # n.b.: we don't check @list.size against max here in case people
      # are migrating

      if hash['shuffle']
        @shuffle = @list.shuffle
        @pos = _idx_of(@shuffle, @list[@pos].track_id) if @pos >= 0
      end
    end
    obj
  end

  def to_hsh(full_list = true)
    h = ivars_to_hash(SIVS)
    h.delete_if { |k,v| TL_DEFAULTS[k] == v }
    unless @list.empty?
      if full_list
        h['list'] = @list.map(&:to_path)
      else
        h['size'] = @list.size
      end
    end
    if @shuffle
      h['shuffle'] = true
      h['pos'] = _idx_of(@list, @shuffle[@pos].track_id) if @pos >= 0
    end
    h
  end

  def initialize
    TL_DEFAULTS.each { |k,v| instance_variable_set("@#{k}", v) }
    @list = []
    @goto_off = @goto_pos = nil
    @track_nr = 0
    @shuffle = false
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
    @shuffle.shuffle! if @shuffle
  end

  def get_tracks(track_ids)
    want = {}
    track_ids.each { |i| want[i] = i }
    rv = []
    @list.each do |t|
      i = want[t.track_id] and rv << [ i, t.to_path ]
    end
    rv
  end

  def _update_pos(pos, prev, list)
    old = prev[pos]
    _idx_of(list, old.track_id)
  end

  def shuffle=(bool)
    prev = @shuffle
    if bool
      list = @shuffle = (prev ||= @list).shuffle
    elsif prev
      @shuffle = false
      list = @list
    else
      return false
    end
    @pos = _update_pos(@pos, prev, list) if @pos >= 0
    @goto_pos = _update_pos(@goto_pos, prev, list) if @goto_pos
  end

  def tracks
    @list.map(&:track_id)
  end

  def advance_track(repeat_ok = true)
    cur = @shuffle || @list
    return if cur.empty?
    prev = cur[@pos] if @consume && @pos >= 0
    # @repeat == 1 for single track repeat
    repeat = repeat_ok ? @repeat : false
    next_pos = @goto_pos || @pos + (repeat == 1 ? 0 : 1)
    next_off = @goto_off # nil by default
    @goto_pos = @goto_off = nil

    if nxt = cur[next_pos]
      @pos = next_pos
      remove_track(prev.track_id) if prev
    else
      remove_track(prev.track_id) if prev
      # reshuffle the tracklist when we've exhausted it
      cur.shuffle! if @shuffle
      return if !repeat || cur.empty?
      next_pos = @pos = 0
      nxt = cur[0]
    end
    [ nxt.to_path, next_off ]
  end

  def cur_track
    @pos >= 0 ? (@shuffle || @list)[@pos] : nil
  end

  def add_track(track, after_track_id = nil, set_as_current = false)
    return false if @list.size >= @max

    track = new_track(track)
    if after_track_id
      idx = _idx_of(@list, after_track_id) or
                                  raise ArgumentError, 'after_track_id invalid'
      if @shuffle
        _idx_of(@shuffle, after_track_id) or
                                  raise ArgumentError, 'after_track_id invalid'
      end
      @list[idx, 1] = [ @list[idx], track ]

      # add into random position if shuffling
      if @shuffle
        idx = rand(@shuffle.size)
        @shuffle[idx, 1] = [ @shuffle[idx], track ]
      end

      if set_as_current
        @pos = idx + 1
      else
        @pos += 1 if @pos > idx
      end
    else # nil = first_track
      @list.unshift(track)

      if @shuffle
        if @shuffle.empty?
          @shuffle << track
          @pos = 0 if set_as_current
        else
          idx = rand(@shuffle.size)
          @shuffle[idx, 1] = [ @shuffle[idx], track ]
          @pos = idx + 1 if set_as_current
        end
      else
        if set_as_current
          @pos = 0
        else
          @pos += 1 if @pos >= 0
        end
      end
    end
    track.track_id
  end

  def _idx_of(list, track_id)
    list.index { |t| t.track_id == track_id }
  end

  def remove_track(track_id)
    idx = _idx_of(@list, track_id) or return false
    track = @list.delete_at(idx)
    if @shuffle
      idx = _idx_of(@shuffle, track_id) or return false
      @shuffle.delete_at(idx)
    end
    len = @list.size
    if @pos >= len
      @pos = len - 1
    elsif idx <= @pos
      @pos -= 1
    end
    @goto_pos = @goto_off = nil # TODO: reposition?
    track.to_path
  end

  def clear
    @list.clear
    @shuffle.clear if @shuffle
    reset
  end

  def go_to(track_id, offset_hhmmss = nil)
    list = @shuffle || @list
    if idx = _idx_of(list, track_id)
      @goto_off = offset_hhmmss
      return list[@goto_pos = idx].to_path
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

  def swap(a_id, b_id)
    ok = { a_id => a_idx = [], b_id => b_idx = [] }
    @list.each_with_index do |t,i|
      ary = ok.delete(t.track_id) or next
      ary[0] = i
      break if ok.empty?
    end
    a_idx = a_idx[0] or return
    b_idx = b_idx[0] or return
    @list[a_idx], @list[b_idx] = @list[b_idx], @list[a_idx]
    unless @shuffle
      [ :@goto_pos, :@pos ].each do |v|
        case instance_variable_get(v)
        when a_idx then instance_variable_set(v, b_idx)
        when b_idx then instance_variable_set(v, a_idx)
        end
      end
    end
    true
  end
end

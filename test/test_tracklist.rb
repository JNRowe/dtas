# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative 'helper'
require 'dtas/tracklist'
class TestTracklist < Testcase

  def list_to_path(tl)
    tl.instance_variable_get(:@list).map(&:to_path)
  end

  def list_add(tl, ary)
    ary.reverse_each { |x| tl.add_track(x) }
  end

  def test_tl_add_tracks
    tl = DTAS::Tracklist.new
    tl.add_track("/foo.flac")
    assert_equal(%w(/foo.flac), list_to_path(tl))

    oids = tl.tracks
    assert_kind_of Array, oids
    assert_equal 1, oids.size
    assert_equal [ [ oids[0], "/foo.flac" ] ], tl.get_tracks(oids)

    tl.add_track("/bar.flac")
    assert_equal(%w(/bar.flac /foo.flac), list_to_path(tl))

    tl.add_track("/after.flac", oids[0])
    assert_equal(%w(/bar.flac /foo.flac /after.flac), list_to_path(tl))
  end

  def test_add_current
    tl = DTAS::Tracklist.new
    list_add(tl, %w(a b c d e f g))
    tl.add_track('/foo.flac', nil, true)
    assert_equal '/foo.flac', tl.cur_track.to_path
  end

  def test_advance_track
    tl = DTAS::Tracklist.new
    ary = %w(a b c d e f g)
    list_add(tl, ary)
    ary.each { |t| assert_equal t, tl.advance_track[0] }
    assert_nil tl.advance_track
    tl.repeat = true
    assert_equal 'a', tl.advance_track[0]
  end

  def _build_mapping(tl)
    tracks = tl.get_tracks(tl.tracks)
    Hash[tracks.map { |(oid,name)| [ name, oid ] }]
  end

  def test_goto
    tl = DTAS::Tracklist.new
    list_add(tl, %w(a b c d e f g))
    mapping = _build_mapping(tl)
    assert_equal 'f', tl.go_to(mapping['f'])
    assert_equal 'f', tl.advance_track[0]
    assert_nil tl.go_to(1 << 128)
    assert_equal 'g', tl.advance_track[0]
  end

  def test_shuffle
    tl = DTAS::Tracklist.new
    exp = %w(a b c d e f g)
    list_add(tl, exp)
    tl.shuffle = true
    assert_equal(exp, list_to_path(tl))
    assert_equal exp.size, tl.shuffle.size
    assert_equal exp, tl.shuffle.map(&:to_path).sort
    tl.shuffle = false
    assert_equal false, tl.shuffle

    tl.instance_variable_set :@pos, 3
    before = tl.cur_track
    3.times do
      tl.shuffle = true
      assert_equal before, tl.cur_track
    end
    x = tl.to_hsh
    assert_equal true, x['shuffle']
    3.times do
      loaded = DTAS::Tracklist.load(x.dup)
      assert_equal before.to_path, loaded.cur_track.to_path
    end
  end

  def test_remove_track
    tl = DTAS::Tracklist.new
    ary = %w(a b c d e f g)
    list_add(tl, ary)
    mapping = _build_mapping(tl)
    ary.each { |t| assert_kind_of Integer, mapping[t] }

    tl.remove_track(mapping['a'])
    assert_equal %w(b c d e f g), list_to_path(tl)

    tl.remove_track(mapping['d'])
    assert_equal %w(b c e f g), list_to_path(tl)

    tl.remove_track(mapping['g'])
    assert_equal %w(b c e f), list_to_path(tl)

    # it'll be a while before OIDs require >128 bits, right?
    tl.remove_track(1 << 128)
    assert_equal %w(b c e f), list_to_path(tl), "no change"
  end
end

# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative 'helper'
require 'dtas/tracklist'
class TestTracklist < Testcase
  def test_tl_add_tracks
    tl = DTAS::Tracklist.new
    tl.add_track("/foo.flac")
    assert_equal(%w(/foo.flac), tl.instance_variable_get(:@list))

    oids = tl.tracks
    assert_kind_of Array, oids
    assert_equal 1, oids.size
    assert_equal [ [ oids[0], "/foo.flac" ] ], tl.get_tracks(oids)

    tl.add_track("/bar.flac")
    assert_equal(%w(/bar.flac /foo.flac), tl.instance_variable_get(:@list))

    tl.add_track("/after.flac", oids[0])
    assert_equal(%w(/bar.flac /foo.flac /after.flac),
                 tl.instance_variable_get(:@list))
  end

  def test_add_current
    tl = DTAS::Tracklist.new
    tl.instance_variable_get(:@list).replace(%w(a b c d e f g))
    tl.add_track('/foo.flac', nil, true)
    assert_equal '/foo.flac', tl.cur_track
  end

  def test_advance_track
    tl = DTAS::Tracklist.new
    tl.instance_variable_get(:@list).replace(%w(a b c d e f g))
    %w(a b c d e f g).each do |t|
      assert_equal t, tl.advance_track
    end
    assert_nil tl.advance_track
    tl.repeat = true
    assert_equal 'a', tl.advance_track
  end

  def _build_mapping(tl)
    tracks = tl.get_tracks(tl.tracks)
    Hash[tracks.map { |(oid,name)| [ name, oid ] }]
  end

  def test_goto
    tl = DTAS::Tracklist.new
    tl.instance_variable_get(:@list).replace(%w(a b c d e f g))
    mapping = _build_mapping(tl)
    assert_equal 'f', tl.go_to(mapping['f'])
    assert_equal 'f', tl.advance_track
    assert_nil tl.go_to(1 << 128)
    assert_equal 'g', tl.advance_track
  end

  def test_remove_track
    tl = DTAS::Tracklist.new
    tl.instance_variable_get(:@list).replace(%w(a b c d e f g))
    mapping = _build_mapping(tl)
    %w(a b c d e f g).each { |t| assert_kind_of Integer, mapping[t] }

    tl.remove_track(mapping['a'])
    assert_equal %w(b c d e f g), tl.instance_variable_get(:@list)

    tl.remove_track(mapping['d'])
    assert_equal %w(b c e f g), tl.instance_variable_get(:@list)

    tl.remove_track(mapping['g'])
    assert_equal %w(b c e f), tl.instance_variable_get(:@list)

    # it'll be a while before OIDs require >128 bits, right?
    tl.remove_track(1 << 128)
    assert_equal %w(b c e f), tl.instance_variable_get(:@list), "no change"
  end
end

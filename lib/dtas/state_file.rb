# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'yaml'
require 'tempfile'

# state file preserves state across restarts of dtas-player
class DTAS::StateFile # :nodoc:
  attr_reader :path

  def initialize(path, do_fsync = false)
    @path = path
    @do_fsync = do_fsync
  end

  def tryload
    YAML.load(IO.binread(@path)) if File.readable?(@path)
  end

  def dump(obj, force_fsync = false)
    yaml = obj.to_hsh.to_yaml.b

    # do not replace existing state file if there are no changes
    # this will be racy if we ever do async dumps or shared state
    # files, but we don't do that...
    return if File.readable?(@path) && IO.binread(@path) == yaml

    dir = File.dirname(@path)
    Tempfile.open(%w(player.state .tmp), dir) do |tmp|
      tmp.binmode
      tmp.write(yaml)
      tmp.flush
      tmp.fsync if @do_fsync || force_fsync
      File.rename(tmp.path, @path)
    end
  end
end

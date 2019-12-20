# Copyright (C) 2013-2019 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'sleepy_penguin'

# used to restart DTAS::Source::SplitFX processing in dtas-player
# if the YAML file is edited
class DTAS::Watchable::InotifyReadableIter < SleepyPenguin::Inotify # :nodoc:
  include DTAS::Watchable::InotifyCommon
  def self.new
    super(:CLOEXEC)
  end
end

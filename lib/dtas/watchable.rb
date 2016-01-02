# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
begin
require 'sleepy_penguin'

# used to restart DTAS::Source::SplitFX processing in dtas-player
# if the YAML file is edited
module DTAS::Watchable # :nodoc:
  class InotifyReadableIter < SleepyPenguin::Inotify # :nodoc:
    def self.new
      super(:CLOEXEC)
    end

    FLAGS = CLOSE_WRITE | MOVED_TO

    def readable_iter
      or_call = false
      while event = take(true) # drain the buffer
        w = @watches[event.wd] or next
        if (event.mask & FLAGS) != 0 && w[event.name]
          or_call = true
        end
      end
      if or_call
        @on_readable.call
        :delete
      else
        :wait_readable
      end
    end

    # we must watch the directory, since
    def watch_files(paths, blk)
      @watches = {} # wd -> { basename -> true }
      @on_readable = blk
      @dir2wd = {}
      Array(paths).each do |path|
        watchdir, watchbase = File.split(File.expand_path(path))
        wd = @dir2wd[watchdir] ||= add_watch(watchdir, FLAGS)
        m = @watches[wd] ||= {}
        m[watchbase] = true
      end
    end
  end

  def watch_begin(blk)
    @ino = InotifyReadableIter.new
    @ino.watch_files(@watch_extra << @infile, blk)
    @ino
  end

  def watch_extra(paths)
    @ino.watch_extra(paths)
  end

  # Closing the inotify descriptor (instead of using inotify_rm_watch)
  # is cleaner because it avoids EINVAL on race conditions in case
  # a directory is deleted: https://lkml.org/lkml/2007/7/9/3
  def watch_end(srv)
    srv.wait_ctl(@ino, :delete)
    @ino = @ino.close
  end
end

rescue LoadError
end

# Copyright (C) 2014, all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later <https://www.gnu.org/licenses/gpl-3.0.txt>
begin
  require 'sleepy_penguin'
rescue LoadError
end

# used to restart DTAS::Source::SplitFX processing in dtas-player
# if the YAML file is edited
module DTAS::Source::Watchable
  class InotifyReadableIter < SleepyPenguin::Inotify
    def self.new
      super(:CLOEXEC)
    end

    FLAGS = CLOSE_WRITE | MOVED_TO

    def readable_iter
      or_call = false
      while event = take(true) # drain the buffer
        if (event.mask & FLAGS) != 0 && @watching[1] == event.name
          or_call = true
        end
      end
      if or_call && @on_readable
        @on_readable.call
        :delete
      else
        :wait_readable
      end
    end

    # we must watch the directory, since
    def watch_file(path, blk)
      @on_readable = blk
      @watching = File.split(File.expand_path(path))
      add_watch(@watching[0], FLAGS)
    end
  end

  def watch_begin(blk)
    @ino = InotifyReadableIter.new
    @ino.watch_file(@infile, blk)
    @ino
  end

  # Closing the inotify descriptor (instead of using inotify_rm_watch)
  # is cleaner because it avoids EINVAL on race conditions in case
  # a directory is deleted: https://lkml.org/lkml/2007/7/9/3
  def watch_end(srv)
    srv.wait_ctl(@ino, :delete)
    @ino = @ino.close
  end
end if defined?(SleepyPenguin::Inotify)

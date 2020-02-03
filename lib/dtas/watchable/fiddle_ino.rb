# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'fiddle'

# used to restart DTAS::Source::SplitFX processing in dtas-player
# if the YAML file is edited
class DTAS::Watchable::InotifyReadableIter # :nodoc:
  include DTAS::Watchable::InotifyCommon

  Inotify_init = Fiddle::Function.new(DTAS.libc['inotify_init1'],
    [ Fiddle::TYPE_INT ],
    Fiddle::TYPE_INT)

  Inotify_add_watch = Fiddle::Function.new(DTAS.libc['inotify_add_watch'],
    [ Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT ],
    Fiddle::TYPE_INT)

  # IO.select compatibility
  attr_reader :to_io  #:nodoc:

  def initialize # :nodoc:
    fd = Inotify_init.call(02000000 | 04000) # CLOEXEC | NONBLOCK
    raise "inotify_init failed: #{Fiddle.last_error}" if fd < 0
    @to_io = DTAS::Nonblock.for_fd(fd)
    @buf = ''.b
    @q = []
  end

  # struct inotify_event {
  #     int      wd;       /* Watch descriptor */
  #     uint32_t mask;     /* Mask describing event */
  #     uint32_t cookie;   /* Unique cookie associating related
  #                           events (for rename(2)) */
  #     uint32_t len;      /* Size of name field */
  #     char     name[];   /* Optional null-terminated name */
  InotifyEvent = Struct.new(:wd, :mask, :cookie, :len, :name) # :nodoc:

  def take(nonblock) # :nodoc:
    event = @q.pop and return event
    case rv = @to_io.read_nonblock(16384, @buf, exception: false)
    when :wait_readable, nil
      return
    else
      until rv.empty?
        hdr = rv.slice!(0,16)
        name = nil
        wd, mask, cookie, len = res = hdr.unpack('iIII')
        wd && mask && cookie && len or
          raise "bogus inotify_event #{res.inspect} hdr=#{hdr.inspect}"
        if len > 0
          name = rv.slice!(0, len)
          name.size == len or raise "short name #{name.inspect} != #{len}"
          name.sub!(/\0+\z/, '') or
            raise "missing: `\\0', inotify_event.name=#{name.inspect}"
          name = DTAS.dedupe_str(name)
        end
        ie = InotifyEvent.new(wd, mask, cookie, len, name)
        if event
          @q << ie
        else
          event = ie
        end
      end # /until rv.empty?
      return event
    end while true
  end

  def add_watch(watchdir, flags)
    wd = Inotify_add_watch.call(@to_io.fileno, watchdir, flags)
    raise "inotify_add_watch failed: #{Fiddle.last_error}" if wd < 0
    wd
  end

  def close
    @to_io = @to_io.close if @to_io
  end
end

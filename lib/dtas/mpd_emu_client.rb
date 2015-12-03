# Copyright (C) 2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)

# emulate the MPD protocol
require_relative '../dtas'
require 'shellwords'

class DTAS::MpdEmuClient # :nodoc:
  attr_reader :to_io

  # protocol version we support
  SERVER = 'MPD 0.13.0'
  MAX_RBUF = 8192
  ACK = {
    ERROR_NOT_LIST: 1,
    ERROR_ARG: 2,
    ERROR_PASSWORD: 3,
    ERROR_PERMISSION: 4,
    ERROR_UNKNOWN: 5,
    ERROR_NO_EXIST: 50,
    ERROR_PLAYLIST_MAX: 51,
    ERROR_SYSTEM: 52,
    ERROR_PLAYLIST_LOAD: 53,
    ERROR_UPDATE_ALREADY: 54,
    ERROR_PLAYER_SYNC: 55,
    ERROR_EXIST: 56,
  }

  def initialize(io)
    @to_io = io
    @rbuf = ''.b
    @wbuf = nil
    @cmd_listnum = 0
    out("OK #{SERVER}\n")
  end

  def dispatch_loop(rbuf)
    while rbuf.sub!(/\A([^\r\n]+)\r?\n/n, '')
      rv = dispatch(Shellwords.split($1))
      next if rv == true
      return rv
    end
    rbuf.size >= MAX_RBUF ? nil : :wait_readable
  end

  def dispatch(argv)
    cmd = argv.shift or return err(:ERROR_UNKNOWN)
    cmd = "mpdcmd_#{cmd}"
    if respond_to?(cmd)
      m = method(cmd)
      params = m.parameters
      rest = params.any? { |x| x[0] == :rest }
      req = params.count { |x| x[0] == :req }
      opt = params.count { |x| x[0] == :opt }
      argc = argv.size
      return err(:ERROR_ARG) if argc < req
      return err(:ERROR_ARG) if !rest && (argc > (req + opt))
      m.call(*argv)
    else
      err(:ERROR_UNKNOWN)
    end
  end

  def err(sym)
    "[#{ACK[sym]}@#@cmd_listnum {}"
  end

  def mpdcmd_ping; out("OK\n"); end
  def mpdcmd_close(*); nil; end

  def mpdcmd_clearerror
    # player_clear_error
    out("OK\n")
  end

  def mpdcmd_stats
    out("artists: \n" \
        "albums: \n" \
        "songs: \n" \
        "uptime: \n" \
        "playtime: \n" \
        "db_playtime: \n" \
        "db_update: \n" \
        "OK\n")
  end

  # returns true on complete, :wait_writable when blocked, or nil on error
  def out(buf)
    buf = buf.b
    if @wbuf
      @wbuf << buf
      :wait_writable
    else
      tot = buf.size
      case rv = @to_io.write_nonblock(buf, exception: false)
      when Integer
        return true if rv == tot
        buf.slice!(0, rv).clear
        tot -= rv
      when :wait_writable
        @wbuf = buf
        return rv
      end while tot > 0
      true # all done
    end
  rescue
    nil # signal EOF up the chain
  end

  def dispatch_rd(buf)
    case rv = @to_io.read_nonblock(MAX_RBUF, buf, exception: false)
    when String then dispatch_loop(@rbuf << rv)
    when :wait_readable, nil then rv
    end
  rescue
    nil
  end

  def dispatch_wr
    tot = @wbuf.size
    case rv = @to_io.write_nonblock(@wbuf, exception: false)
    when Integer
      @wbuf.slice!(0, rv).clear
      tot -= rv
      return :wait_readable if tot == 0
    when :wait_writable then return rv
    end while true
  rescue
    nil
  end

  def hash
    @to_io.fileno
  end
end

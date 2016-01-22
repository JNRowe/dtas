# Copyright (C) 2015-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true

require_relative '../dtas'

# Used for mpd emulation currently, but dtas-player might use this eventually
class DTAS::ServerLoop
  def initialize(listeners, client_class)
    @rd = {}
    @wr = {}
    @rbuf = ''.b
    @client_class = client_class
    listeners.each { |l| @rd[l] = true }
  end

  def run_forever
    begin
      r = IO.select(@rd.keys, @wr.keys) or next
      r[0].each { |rd| do_read(rd) }
      r[1].each { |wr| do_write(wr) }
    end while true
  end

  def do_write(wr)
    case wr.dispatch_wr
    when :wait_readable
      @wr.delete(wr)
      @rd[wr] = true
    when nil
      @wr.delete(wr)
      wr.to_io.close
    # when :wait_writable # do nothing
    end
  end

  def do_read(rd)
    case rd
    when @client_class
      case rd.dispatch_rd(@rbuf)
      when :wait_writable
        @rd.delete(rd)
        @wr[rd] = true
      when nil
        @rd.delete(rd)
        rd.to_io.close
      # when :wait_readable : do nothing
      end
    else
      case io = rd.accept_nonblock(exception: false)
      when :wait_readable then break
      when IO then @rd[@client_class.new(io)] = true
      end while true
    end
  end
end

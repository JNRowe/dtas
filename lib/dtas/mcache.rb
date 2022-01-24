# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
# encoding: binary
require_relative '../dtas'

class DTAS::Mcache
  def initialize(shift = 8, ttl = 60)
    @mask = (1 << shift) - 1
    @ttl = ttl
    @tbl = []
  end

  def lookup(infile)
    bucket = infile.hash & @mask
    st = nil
    if cur = @tbl[bucket]
      if cur[:infile] == infile && (DTAS.now - cur[:btime]) < @ttl
        begin
          st = File.stat(infile)
          return cur if cur[:ctime] == st.ctime
        rescue
        end
      end
    end
    return unless block_given?
    @tbl[bucket] = begin
      cur = cur ? cur.clear : {}
      begin
        st ||= File.stat(infile)
        cur[:ctime] = st.ctime
      rescue
        return
      end
      if ret = yield(infile, cur)
        ret[:infile] = infile.frozen? ? infile : -(infile.dup)
        ret[:btime] = DTAS.now
      end
      ret
    end
  end
end

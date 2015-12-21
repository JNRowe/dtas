# -*- encoding: binary -*-
# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative '../dtas'
require_relative 'xs'
require_relative 'process'
require_relative 'sigevent'

# backend for the dtas-partstats(1) command
# Unlike the stuff for dtas-player, dtas-partstats is fairly tied to sox
class DTAS::PartStats # :nodoc:
  CMD = 'sox "$INFILE" -n $TRIMFX $SOXFX stats $STATSOPTS'
  include DTAS::Process
  include DTAS::SpawnFix
  attr_reader :key_idx
  attr_reader :key_width

  class TrimPart < Struct.new(:tbeg, :tlen, :rate) # :nodoc:
    def sec
      tbeg / rate
    end

    def hhmmss
      Time.at(sec).strftime("%H:%M:%S")
    end
  end

  def initialize(infile)
    @infile = infile
    %w(samples rate channels).each do |iv|
      sw = iv[0] # -s, -r, -c
      i = qx(%W(soxi -#{sw} #@infile)).to_i
      raise ArgumentError, "invalid #{iv}: #{i}" if i <= 0
      instance_variable_set("@#{iv}", i)
    end

    # "Pk lev dB" => 1, "RMS lev dB" => 2, ...
    @key_nr = 0
    @key_idx = Hash.new { |h,k| h[k] = (@key_nr += 1) }
    @key_width = {}
  end

  def partitions(chunk_sec)
    n = 0
    part_samples = chunk_sec * @rate
    rv = []
    begin
      rv << TrimPart.new(n, part_samples, @rate)
      n += part_samples
    end while n < @samples
    rv
  end

  def partstats_spawn(trim_part, opts)
    rd, wr = IO.pipe
    env = opts[:env]
    env = env ? env.dup : {}
    env["INFILE"] = xs(@infile)
    env["TRIMFX"] = "trim #{trim_part.tbeg}s #{trim_part.tlen}s"
    opts = { pgroup: true, close_others: true, err: wr }
    pid = spawn(env, CMD, opts)
    wr.close
    [ pid, rd ]
  end

  def run(opts = {})
    sev = DTAS::Sigevent.new
    trap(:CHLD) { sev.signal }
    jobs = opts[:jobs] || 2
    pids = {}
    rset = {}
    stats = []
    fails = []
    do_spawn = lambda do |trim_part|
      pid, rpipe = partstats_spawn(trim_part, opts)
      rset[rpipe] = [ trim_part, ''.b ]
      pids[pid] = [ trim_part, rpipe ]
    end

    parts = partitions(opts[:chunk_length] || 10)
    jobs.times do
      trim_part = parts.shift or break
      do_spawn.call(trim_part)
    end

    rset[sev] = true

    while pids.size > 0
      r = IO.select(rset.keys) or next
      r[0].each do |rd|
        if DTAS::Sigevent === rd
          rd.readable_iter do |_,_|
            begin
              pid, status = Process.waitpid2(-1, Process::WNOHANG)
              pid or break
              done = pids.delete(pid)
              done_part = done[0]
              if status.success?
                trim_part = parts.shift and do_spawn.call(trim_part)
                puts "DONE #{done_part}" if $DEBUG
              else
                fails << [ done_part, status ]
              end
            rescue Errno::ECHILD
              break
            end while true
          end
        else
          # spurious wakeup should not happen on local pipes,
          # so readpartial should be safe
          trim_part, buf = rset[rd]
          begin
            buf << rd.readpartial(666)
          rescue EOFError
            rset.delete(rd)
            rd.close
            parse_stats(stats, trim_part, buf)
          end
        end
      end
    end

    return stats if fails.empty? && parts.empty?
    fails.each do |(trim_part,status)|
      warn "FAIL #{status.inspect} #{trim_part}"
    end
    false
  ensure
    sev.close
  end

# "sox INFILE -n stats" example output
=begin
             Overall     Left      Right
DC offset   0.001074  0.000938  0.001074
Min level  -0.997711 -0.997711 -0.997711
Max level   0.997681  0.997681  0.997681
Pk lev dB      -0.02     -0.02     -0.02
RMS lev dB    -10.38     -9.90    -10.92
RMS Pk dB      -4.62     -4.62     -5.10
RMS Tr dB     -87.25    -86.58    -87.25
Crest factor       -      3.12      3.51
Flat factor    19.41     19.66     18.89
Pk count        117k      156k     77.4k
Bit-depth      16/16     16/16     16/16
Num samples    17.2M
Length s     389.373
Scale max   1.000000
Window s       0.050

becomes:
  [
    TrimPart,
    [ -0.02, -0.02, -0.02 ], # Pk lev dB
    [ -10.38, -9.90, -10.92 ], # RMS lev dB
    ...
  ]
=end

  def parse_stats(stats, trim_part, buf)
    trim_row = [ trim_part ]
    buf.split(/\n/).each do |line|
      do_map = true
      case line
      when /\A(\S+ \S+ dB)\s/, /\A(Crest factor)\s+-\s/
        nshift = 3
      when /\A(Flat factor)\s/
        nshift = 2
      when /\A(Pk count)\s/
        nshift = 2
        do_map = false
      else
        next
      end
      key = $1
      key.freeze
      key_idx = @key_idx[key]
      parts = line.split(/\s+/)
      nshift.times { parts.shift } # remove stuff we don't need
      @key_width[key] = parts.size
      trim_row[key_idx] = do_map ? parts.map!(&:to_f) : parts
    end
    stats[trim_part.tbeg / trim_part.tlen] = trim_row
  end
end

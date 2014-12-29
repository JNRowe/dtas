# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../dtas'
require_relative 'parse_time'
require 'shellwords'

class DTAS::TrimFX
  include DTAS::ParseTime

  attr_reader :tbeg
  attr_reader :tlen
  attr_reader :cmd

  def initialize(args)
    args = args.dup
    case args.shift
    when "trim"
      parse_trim!(args)
    when "all"
      @tbeg = 0
      @tlen = nil
    else
      raise ArgumentError, "#{args.inspect} not understood"
    end
    case tmp =  args.shift
    when "sh" then @cmd = args
    when "sox" then tfx_sox(args)
    when "eca" then tfx_eca(args)
    when nil
      @cmd = []
    else
      raise ArgumentError, "unknown effect type: #{tmp}"
    end
  end

  def tfx_sox(args)
    @cmd = %w(sox $SOXIN $SOXOUT $TRIMFX)
    @cmd.concat(args)
  end

  def tfx_eca(args)
    @cmd = %w(sox $SOXIN $SOX2ECA $TRIMFX)
    @cmd.concat(%w(| ecasound $ECAFMT -i stdin -o stdout))
    @cmd.concat(args)
    @cmd.concat(%w(| sox $ECA2SOX - $SOXOUT))
  end

  def to_sox_arg(format)
    if @tbeg && @tlen
      beg = @tbeg * format.rate
      len = @tlen * format.rate
      %W(trim #{beg.round}s #{len.round}s)
    elsif @tbeg
      return [] if @tbeg == 0
      beg = @tbeg * format.rate
      %W(trim #{beg.round}s)
    else
      []
    end
  end

  # tries to interpret "trim" time args the same way the sox trim effect does
  # This takes _time_ arguments only, not sample counts;
  # otherwise, deviations from sox are considered bugs in dtas
  def parse_trim!(args)
    tbeg = parse_time(args.shift)
    if args[0] =~ /\A=?[\d\.]+\z/
      tlen = args.shift
      is_stop_time = tlen.sub!(/\A=/, "") ? true : false
      tlen = parse_time(tlen)
      tlen = tlen - tbeg if is_stop_time
    else
      tlen = nil
    end
    @tbeg = tbeg
    @tlen = tlen
  end

  def <=>(other)
    tbeg <=> other.tbeg
  end

  # for stable sorting
  class TFXSort < Struct.new(:tfx, :idx)
    def <=>(other)
      cmp = tfx <=> other.tfx
      0 == cmp ? idx <=> other.idx : cmp
    end
  end

  # sorts and converts an array of TrimFX objects into non-overlapping arrays
  # of epochs
  #
  # input:
  #   [ tfx1, tfx2, tfx3, ... ]
  #
  # output:
  #   [
  #     [ tfx1 ],         # first epoch
  #     [ tfx2, tfx3 ],   # second epoch
  #     ...
  #   ]
  # There are multiple epochs only if ranges overlap,
  # There is only one epoch if there are no overlaps
  def self.schedule(ary)
    sorted = []
    ary.each_with_index { |tfx, i| sorted << TFXSort[tfx, i] }
    sorted.sort!
    rv = []
    epoch = 0
    prev_end = 0
    defer = []

    begin
      while tfxsort = sorted.shift
        tfx = tfxsort.tfx
        if tfx.tbeg >= prev_end
          # great, no overlap, append to the current epoch
          prev_end = tfx.tbeg + tfx.tlen
          (rv[epoch] ||= []) << tfx
        else
          # overlapping region, we'll need a new epoch
          defer << tfxsort
        end
      end

      if defer[0] # do we need another epoch?
        epoch += 1
        sorted = defer
        defer = []
        prev_end = 0
      end
    end while sorted[0]

    rv
  end

  # like schedule, but fills in the gaps with pass-through (no-op) TrimFX objs
  # This does not change the number of epochs.
  def self.expand(ary, total_len)
    rv = []
    schedule(ary).each_with_index do |sary, epoch|
      tip = 0
      dst = rv[epoch] = []
      while tfx = sary.shift
        if tfx.tbeg > tip
          # fill in the previous gap
          nfx = new(%W(trim #{tip} =#{tfx.tbeg}))
          dst << nfx
          dst << tfx
          tip = tfx.tbeg + tfx.tlen
        end
      end
      if tip < total_len # fill until the last chunk
        nfx = new(%W(trim #{tip} =#{total_len}))
        dst << nfx
      end
    end
    rv
  end
end

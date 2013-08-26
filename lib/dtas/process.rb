# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'shellwords'
require 'io/wait'
require_relative '../dtas'
module DTAS::Process # :nodoc:
  PIDS = {}

  def self.reaper
    begin
      pid, status = Process.waitpid2(-1, Process::WNOHANG)
      pid or return
      obj = PIDS.delete(pid)
      yield status, obj
    rescue Errno::ECHILD
      return
    end while true
  end

  # for long-running processes (sox/play/ecasound filters)
  def dtas_spawn(env, cmd, opts)
    opts = { close_others: true, pgroup: true }.merge!(opts)

    # stringify env, integer values are easier to type unquoted as strings
    env.each { |k,v| env[k] = v.to_s }

    pid = begin
      Process.spawn(env, cmd, opts)
    rescue Errno::EINTR # Ruby bug?
      retry
    end
    warn [ :spawn, pid, cmd ].inspect if $DEBUG
    @spawn_at = Time.now.to_f
    PIDS[pid] = self
    pid
  end

  # this is like backtick, but takes an array instead of a string
  # This will also raise on errors
  def qx(env, cmd = {}, opts = {})
    unless Hash === env
      cmd, opts = env, cmd
      env = {}
    end
    r, w = IO.pipe
    opts = opts.merge(out: w)
    r.binmode
    if err = opts[:err]
      re, we = IO.pipe
      re.binmode
      opts[:err] = we
    end
    pid = begin
      Process.spawn(env, *cmd, opts)
    rescue Errno::EINTR # Ruby bug?
      retry
    end
    w.close
    if err
      we.close
      res = ""
      want = { r => res, re => err }
      begin
        readable = IO.select(want.keys) or next
        readable[0].each do |io|
          bytes = io.nread
          begin
            want[io] << io.read_nonblock(bytes > 0 ? bytes : 11)
          rescue Errno::EAGAIN
            # spurious wakeup, bytes may be zero
          rescue EOFError
            want.delete(io)
          end
        end
      end until want.empty?
      re.close
    else
      res = r.read
    end
    r.close
    _, status = Process.waitpid2(pid)
    return res if status.success?
    raise RuntimeError, "`#{Shellwords.join(cmd)}' failed: #{status.inspect}"
  end

  # XXX only for DTAS::Source::{Sox,Av}.try
  module_function :qx
end

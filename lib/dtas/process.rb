# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'io/wait'
require_relative '../dtas'
require_relative 'xs'

module DTAS::Process # :nodoc:
  PIDS = {}
  include DTAS::XS

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

  # expand common shell constructs based on environment variables
  # this is order-dependent, but Ruby 1.9+ hashes are already order-dependent
  def env_expand(env, opts)
    env = env.dup
    if false == opts.delete(:expand)
      env.each do |key, val|
        Numeric === val and env[key] = val.to_s
      end
    else
      env.each do |key, val|
        case val
        when Numeric # stringify numeric values to simplify users' lives
          env[key] = val.to_s
        when /[\`\$]/ # perform variable/command expansion
          tmp = env.dup
          tmp.delete(key)
          val = qx(tmp, "echo #{val}", expand: false)
          env[key] = val.chomp
        end
      end
    end
  end

  # for long-running processes (sox/play/ecasound filters)
  def dtas_spawn(env, cmd, opts)
    opts = { close_others: true, pgroup: true }.merge!(opts)
    env = env_expand(env, opts)

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
    no_raise = opts.delete(:no_raise)
    if err_str = opts.delete(:err_str)
      re, we = IO.pipe
      re.binmode
      opts[:err] = we
    end
    env = env_expand(env, opts)
    pid = begin
      Process.spawn(env, *cmd, opts)
    rescue Errno::EINTR # Ruby bug?
      retry
    end
    w.close
    if err_str
      we.close
      res = "".b
      want = { r => res, re => err_str }
      begin
        readable = IO.select(want.keys) or next
        readable[0].each do |io|
          begin
            want[io] << io.read_nonblock(2000)
          rescue Errno::EAGAIN
            # spurious wakeup, bytes may be zero
          rescue EOFError
            want.delete(io)
          end
        end
      end until want.empty?
      re.close
    else
      res = r.read # read until EOF
    end
    r.close
    _, status = Process.waitpid2(pid)
    return res if status.success?
    return status if no_raise
    raise RuntimeError, "`#{xs(Array(cmd))}' failed: #{status.inspect}"
  end
end

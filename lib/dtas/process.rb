# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'io/wait'
require 'shellwords'
require_relative '../dtas'
require_relative 'xs'
require_relative 'nonblock'

# process management helpers
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
  # This recurses
  def env_expand(env, opts)
    env = env.dup
    if false == opts.delete(:expand)
      env.each do |key, val|
        Numeric === val and env[key] = val.to_s
      end
    else
      env.each do |key, val|
        case val = env_expand_i(env, key, val)
        when Array
          val.flatten!
          env[key] = Shellwords.join(val)
        end
      end
    end
  end

  def env_expand_i(env, key, val)
    case val
    when Numeric # stringify numeric values to simplify users' lives
      env[key] = val.to_s
    when /[\`\$]/ # perform variable/command expansion
      tmp = env.dup
      tmp.delete(key)
      tmp.each do |k,v|
        # best effort, this can get wonky
        tmp[k] = Shellwords.join(v.flatten) if Array === v
      end
      val = qx(tmp, "echo #{val}", expand: false)
      env[key] = val.chomp
    when Array
      env[key] = env_expand_ary(env, key, val)
    else
      val
    end
  end

  # warning, recursion:
  def env_expand_ary(env, key, val)
    val.map { |v| env_expand_i(env.dup, key, v) }
  end

  # for long-running processes (sox/play/ecasound filters)
  def dtas_spawn(env, cmd, opts)
    opts = { close_others: true, pgroup: true }.merge!(opts)
    env = env_expand(env, opts)

    pid = spawn(env, cmd, opts)
    warn [ :spawn, pid, cmd ].inspect if $DEBUG
    @spawn_at = DTAS.now
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
    buf = ''.b
    r, w = DTAS::Nonblock.pipe
    opts = opts.merge(out: w)
    r.binmode
    no_raise = opts.delete(:no_raise)
    if err_str = opts.delete(:err_str)
      re, we = DTAS::Nonblock.pipe
      re.binmode
      opts[:err] = we
    end
    env = env_expand(env, opts)
    pid = spawn(env, *cmd, opts)
    w.close
    if err_str
      we.close
      res = ''.b
      want = { r => res, re => err_str }
      begin
        readable = IO.select(want.keys) or next
        readable[0].each do |io|
          case rv = io.read_nonblock(2000, buf, exception: false)
          when :wait_readable # spurious wakeup, bytes may be zero
          when nil then want.delete(io)
          else
            want[io] << rv
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
    raise RuntimeError, "`#{xs(cmd)}' failed: #{status.inspect}"
  end
end

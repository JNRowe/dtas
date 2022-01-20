# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require_relative '../dtas'

module DTAS::Pipeline # :nodoc:
  # Process.spawn wrapper which supports running Proc-like objects in
  # a separate process, not just external commands.
  # Returns the pid of the spawned process
  def pspawn(env, cmd, rdr = {})
    case cmd
    when Array
      spawn(env, *cmd, rdr)
    else # support running Proc-like objects, too:
      fork do
        ENV.update(env) if env

        # setup redirects
        [ $stdin, $stdout, $stderr ].each_with_index do |io, fd|
          dst = rdr[fd] and io.reopen(dst)
        end

        # close all other pipes, since we can't rely on FD_CLOEXEC
        # (as we do not exec, here)
        rdr.each do |k, v|
          k.close if v == :close
        end
        cmd.call
      end
    end
  end

  # +pipeline+ is an Array of (Arrays or Procs)
  def run_pipeline(env, pipeline)
    pids = {} # pid => pipeline index
    work = pipeline.dup
    last = work.pop
    nr = work.size
    rdr = {} # redirect mapping for Process.spawn

    # we need to make sure pipes are closed in any forked processes
    # (they are redirected to stdin or stdout, first)
    pipes = nr.times.map { IO.pipe.each { |io| rdr[io] = :close } }

    # start the first and last commands first, they only have one pipe, each
    last_pid = pspawn(env, last, rdr.merge(0 => pipes[-1][0]))
    pids[last_pid] = nr
    first = work.shift
    first_pid = pspawn(env, first, rdr.merge(1 => pipes[0][1]))
    pids[first_pid] = 0

    # start the middle commands, they both have two pipes:
    work.each_with_index do |cmd, i|
      pid = pspawn(env, cmd, rdr.merge(0 => pipes[i][0], 1 => pipes[i+1][1]))
      pids[pid] = i + 1
    end

    # all pipes handed off to children, close so they see EOF
    pipes.flatten!.each(&:close).clear

    # wait for children to finish
    fails = []
    until pids.empty?
      pid, status = Process.waitpid2(-1)
      nr = pids.delete(pid)
      status.success? or
        fails << "reaped #{nr} #{pipeline[nr].inspect} #{status.inspect}"
    end
    # behave like "set -o pipefail" in bash
    raise fails.join("\n") if fails[0]
  end
end

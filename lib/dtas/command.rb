# -*- encoding: binary -*-
# :stopdoc:
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
# common code for wrapping SoX/ecasound/... commands
require_relative 'serialize'
require 'shellwords'

module DTAS::Command
  include DTAS::Serialize
  attr_reader :pid
  attr_reader :to_io
  attr_accessor :command
  attr_accessor :env
  attr_accessor :spawn_at

  COMMAND_DEFAULTS = {
    "env" => {},
    "command" => nil,
  }

  def command_init(defaults = {})
    @pid = nil
    @to_io = nil
    @spawn_at = nil
    COMMAND_DEFAULTS.merge(defaults).each do |k,v|
      v = v.dup if Hash === v || Array === v
      instance_variable_set("@#{k}", v)
    end
  end

  def kill(sig = :TERM)
    # always kill the pgroup since we run subcommands in their own shell
    Process.kill(sig, -@pid)
  end

  def on_death(status)
    @pid = nil
  end

  def command_string
    @command
  end
end

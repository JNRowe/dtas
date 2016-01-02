# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require_relative 'serialize'
require 'shellwords'

# common code for wrapping SoX/ecasound/... commands
module DTAS::Command # :nodoc:
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

  def on_death(status)
    @pid = nil
  end

  def command_string
    @command
  end
end

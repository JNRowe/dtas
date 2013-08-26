# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require_relative '../../dtas'
require_relative '../source'
require_relative '../command'
require_relative '../serialize'

class DTAS::Source::Cmd # :nodoc:
  require_relative '../source/common'

  include DTAS::Command
  include DTAS::Process
  include DTAS::Source::Common
  include DTAS::Serialize

  SIVS = %w(command env)

  def initialize(command)
    command_init(command: command)
  end

  def source_dup
    rv = self.class.new
    SIVS.each { |iv| rv.__send__("#{iv}=", self.__send__(iv)) }
    rv
  end

  def to_hash
    ivars_to_hash(SIVS)
  end

  alias to_hsh to_hash

  def spawn(format, rg_state, opts)
    raise "BUG: #{self.inspect}#spawn called twice" if @to_io
    e = format.to_env
    @pid = dtas_spawn(e.merge!(@env), command_string, opts)
  end
end
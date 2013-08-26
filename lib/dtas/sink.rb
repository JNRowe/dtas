# -*- encoding: binary -*-
# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'yaml'
require_relative '../dtas'
require_relative 'pipe'
require_relative 'process'
require_relative 'command'
require_relative 'format'
require_relative 'serialize'
require_relative 'writable_iter'

# this is a sink (endpoint, audio enters but never leaves)
class DTAS::Sink # :nodoc:
  attr_accessor :prio    # any Integer
  attr_accessor :active  # boolean
  attr_accessor :name
  attr_accessor :pipe_size
  attr_accessor :nonblock

  include DTAS::Command
  include DTAS::Process
  include DTAS::Serialize
  include DTAS::WritableIter

  SINK_DEFAULTS = COMMAND_DEFAULTS.merge({
    "name" => nil, # order matters, this is first
    "command" => "exec play -q $SOXFMT -",
    "prio" => 0,
    "nonblock" => false,
    "pipe_size" => nil,
    "active" => false,
  })

  DEVFD_RE = %r{/dev/fd/([a-zA-Z]\w*)\b}

  # order matters for Ruby 1.9+, this defines to_hsh serialization so we
  # can make the state file human-friendly
  SIVS = %w(name env command prio nonblock pipe_size active)

  def initialize
    command_init(SINK_DEFAULTS)
    writable_iter_init
    @sink = self
  end

  # allow things that look like audio device names ("hw:1,0" , "/dev/dsp")
  # or variable names.
  def valid_name?(s)
    !!(s =~ %r{\A[\w:,/-]+\z})
  end

  def self.load(hash)
    sink = new
    return sink unless hash
    (SIVS & hash.keys).each do |k|
      sink.instance_variable_set("@#{k}", hash[k])
    end
    sink.valid_name?(sink.name) or raise ArgumentError, "invalid sink name"
    sink
  end

  def parse(str)
    inputs = {}
    str.scan(DEVFD_RE) { |w| inputs[w[0]] = nil }
    inputs
  end

  def on_death(status)
    super
  end

  def spawn(format, opts = {})
    raise "BUG: #{self.inspect}#spawn called twice" if @pid
    rv = []

    pclass = @nonblock ? DTAS::PipeNB : DTAS::Pipe

    cmd = command_string
    inputs = parse(cmd)

    if inputs.empty?
      # /dev/fd/* not specified in the command, assume one input for stdin
      r, w = pclass.new
      w.pipe_size = @pipe_size if @pipe_size
      inputs[:in] = opts[:in] = r
      w.sink = self
      rv << w
    else
      # multiple inputs, fun!, we'll tee to them
      inputs.each_key do |name|
        r, w = pclass.new
        w.pipe_size = @pipe_size if @pipe_size
        inputs[name] = r
        w.sink = self
        rv << w
      end
      opts[:in] = "/dev/null"

      # map to real /dev/fd/* values and setup proper redirects
      cmd = cmd.gsub(DEVFD_RE) do
        read_fd = inputs[$1].fileno
        opts[read_fd] = read_fd # do not close-on-exec
        "/dev/fd/#{read_fd}"
      end
    end

    @pid = dtas_spawn(format.to_env.merge!(@env), cmd, opts)
    inputs.each_value { |rpipe| rpipe.close }
    rv
  end

  def to_hash
    ivars_to_hash(SIVS)
  end

  def to_hsh
    to_hash.delete_if { |k,v| v == SINK_DEFAULTS[k] }
  end
end

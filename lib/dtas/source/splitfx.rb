# Copyright (C) all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
require 'yaml'
require_relative 'sox'
require_relative '../splitfx'
require_relative '../watchable'

class DTAS::Source::SplitFX < DTAS::Source::Sox # :nodoc:
  MAX_YAML_SIZE = 512 * 1024
  attr_writer :sox, :sfx
  include DTAS::Watchable if defined?(DTAS::Watchable)

  SPLITFX_DEFAULTS = SOX_DEFAULTS.merge(
    "command" => "#{SOX_DEFAULTS["command"]} $FX",
    "tryorder" => 3,
  )

  def initialize(sox = DTAS::Source::Sox.new)
    command_init(SPLITFX_DEFAULTS)
    @watch_extra = []
    @sox = sox
  end

  def try(ymlfile, offset = nil, trim = nil)
    @splitfx = @ymlhash = nil
    st = File.stat(ymlfile)
    return false if !st.file? || st.size > MAX_YAML_SIZE

    # read 4 bytes first to ensure we have a YAML file with a hash:
    buf = "".dup
    File.open(ymlfile, "rb") do |fp|
      return false if fp.read(4, buf) != "---\n"
      buf << fp.read
    end

    sfx = DTAS::SplitFX.new
    Dir.chdir(File.dirname(ymlfile)) do # ugh
      @ymlhash = DTAS.yaml_load(buf)
      @ymlhash['tracks'] ||= [ "t 0 default" ]
      sfx.import(@ymlhash)
      sfx.infile.replace(File.expand_path(sfx.infile))
    end
    @splitfx = sfx
    @infile = ymlfile
    sox = @sox.try(sfx.infile, offset, trim) or return false
    rv = source_file_dup(ymlfile, offset, trim)
    rv.sox = sox
    rv.env = sfx.env
    rv.sfx = sfx
    rv
  rescue => e
    warn "#{e.message} (#{e.class})"
    false
  end

  def __load_comments
    if c = @ymlhash["comments"]
      return c.each { |k,v| c[k] = v.to_s }
    end
    @sox.__load_comments
  end

  def command_string
    @ymlhash["command"] || super
  end

  def src_spawn(player_format, rg_state, opts)
    raise "BUG: #{self.inspect}#src_spawn called twice" if @to_io
    e = @env.merge!(player_format.to_env)
    @sfx.infile_env(e, @sox.infile)

    # watch any scripts or files the command in the YAML file refers to
    if c = @sfx.command
      @sfx.expand_cmd(e, c).each do |f|
        File.readable?(f) and @watch_extra << f
      end
    end

    # allow users to specify explicit depdendencies to watch for edit
    case extra = @ymlhash['deps']
    when Array, String
      @watch_extra.concat(Array(extra))
    end

    # make sure these are visible to the "current" command...
    e["TRIMFX"] = trimfx
    e["RGFX"] = rg_state.effect(self) || nil
    e.merge!(@rg.to_env) if @rg

    @pid = dtas_spawn(e, command_string, opts)
  end

  def to_hsh
    to_hash.delete_if { |k,v| v == SPLITFX_DEFAULTS[k] }
  end

  def format
    @sox.format
  end

  def samples!
    @sox.samples!
  end

  def samples
    @sox.samples
  end

  def duration
    @sox.duration
  end

  def source_defaults
    SPLITFX_DEFAULTS
  end

  def cuebreakpoints
    @splitfx.cuebreakpoints
  end
end

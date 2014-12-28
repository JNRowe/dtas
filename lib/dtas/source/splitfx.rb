# Copyright (C) 2014, all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later <https://www.gnu.org/licenses/gpl-3.0.txt>
require 'yaml'
require_relative 'sox'
require_relative '../splitfx'
require_relative 'watchable'

class DTAS::Source::SplitFX < DTAS::Source::Sox # :nodoc:
  MAX_YAML_SIZE = 512 * 1024
  attr_writer :sox
  include DTAS::Source::Watchable if defined?(DTAS::Source::Watchable)

  SPLITFX_DEFAULTS = SOX_DEFAULTS.merge(
    "command" => "#{SOX_DEFAULTS["command"]} $FX",
    "tryorder" => 3,
  )

  def initialize(sox = DTAS::Source::Sox.new)
    command_init(SPLITFX_DEFAULTS)
    @sox = sox
  end

  def try(ymlfile, offset = nil)
    @splitfx = @ymlhash = nil
    st = File.stat(ymlfile)
    return false if !st.file? || st.size > MAX_YAML_SIZE

    # read 4 bytes first to ensure we have a YAML file with a hash:
    buf = ""
    File.open(ymlfile, "rb") do |fp|
      return false if fp.read(4, buf) != "---\n"
      buf << fp.read
    end

    sfx = DTAS::SplitFX.new
    begin
      Dir.chdir(File.dirname(ymlfile)) do # ugh
        sfx.import(@ymlhash = YAML.load(buf))
        sfx.infile.replace(File.expand_path(sfx.infile))
      end
      @splitfx = sfx
    rescue
      return false
    end
    @infile = ymlfile
    sox = @sox.try(sfx.infile, offset) or return false
    rv = source_file_dup(ymlfile, offset)
    rv.sox = sox
    rv.env = sfx.env
    rv
  end

  def __load_comments
    @ymlhash["comments"] || @sox.__load_comments
  end

  def command_string
    @ymlhash["command"] || super
  end

  def spawn(player_format, rg_state, opts)
    raise "BUG: #{self.inspect}#spawn called twice" if @to_io
    e = @env.merge!(player_format.to_env)
    e["INFILE"] = @sox.infile

    # make sure these are visible to the "current" command...
    e["TRIMFX"] = @offset ? "trim #@offset" : nil
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

  def source_defaults
    SPLITFX_DEFAULTS
  end

  def cuebreakpoints
    @splitfx.cuebreakpoints
  end
end

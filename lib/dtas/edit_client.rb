# Copyright (C) 2013-2014, Eric Wong <e@80x24.org> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'tempfile'
require 'yaml'
require_relative 'unix_client'
require_relative 'disclaimer'

# common code between dtas-sourceedit and dtas-sinkedit
module DTAS::EditClient # :nodoc:
  def editor
    %w(VISUAL EDITOR).each do |key|
      v = ENV[key] or next
      v.empty? and next
      return v
    end
    "vi"
  end

  def client_socket
    DTAS::UNIXClient.new
  rescue
    e = "DTAS_PLAYER_SOCK=#{DTAS::UNIXClient.default_path}"
    abort "dtas-player not running on #{e}"
  end

  def tmpyaml
    tmp = Tempfile.new(%W(#{File.basename($0)} .yml))
    tmp.sync = true
    tmp.binmode
    tmp
  end

  def update_cmd_env(cmd, orig, updated)
    if env = updated["env"]
      env.each do |k,v|
        cmd << (v.nil? ? "env##{k}" : "env.#{k}=#{v}")
      end
    end

    # remove deleted env
    if orig_env = orig["env"]
      env ||= {}
      deleted_keys = orig_env.keys - env.keys
      deleted_keys.each { |k| cmd << "env##{k}" }
    end
  end
end

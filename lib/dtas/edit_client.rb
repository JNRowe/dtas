# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
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
    'vi'.freeze
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

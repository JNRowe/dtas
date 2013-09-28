# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require 'tempfile'
include Rake::DSL
task "NEWS" do
  latest = nil
  fp = Tempfile.new("NEWS", ".")
  fp.sync = true
  `git tag -l`.split(/\n/).reverse.each do |tag|
    %r{\Av(.+)} =~ tag or next
    version = $1
    header, subject, body = `git cat-file tag #{tag}`.split(/\n\n/, 3)
    header = header.split(/\n/)
    tagger = header.grep(/\Atagger /)[0]
    time = Time.at(tagger.split(/ /)[-2].to_i).utc
    latest ||= time
    date = time.strftime("%Y-%m-%d")
    fp.puts "# #{version} / #{date}\n\n#{subject}"
    if body && body.strip.size > 0
      fp.puts "\n\n#{body}"
    end
    fp.puts
  end
  fp.puts "Unreleased" unless fp.size > 0
  fp.puts "# COPYRIGHT"
  bdfl = 'Eric Wong <normalperson@yhbt.net>'
  fp.puts "Copyright (C) 2013, #{bdfl} and all contributors"
  fp.puts "License: GPLv3 or later (http://www.gnu.org/licenses/gpl-3.0.txt)"
  fp.rewind
  assert_equal fp.read, File.read("NEWS") rescue nil
  fp.chmod 0644
  File.rename(fp.path, "NEWS")
  fp.close!
end

task rsync_docs: "NEWS" do
  dest = ENV["RSYNC_DEST"] || "80x24.org:/srv/dtas/"
  top = %w(INSTALL NEWS README COPYING)
  files = []

  # git-set-file-times is distributed with rsync,
  # Also available at: http://yhbt.net/git-set-file-times
  # on Debian systems: /usr/share/doc/rsync/scripts/git-set-file-times.gz
  sh("git", "set-file-times", "Documentation", "examples", *top)

  `git ls-files Documentation/*.txt`.split(/\n/).concat(top).each do |txt|
    gz = "#{txt}.gz"
    tmp = "#{gz}.#$$"
    sh("gzip -9 < #{txt} > #{tmp}")
    st = File.stat(txt)
    File.utime(st.atime, st.mtime, tmp) # make nginx gzip_static happy
    File.rename(tmp, gz)
    files << txt
    files << gz
  end
  sh("rsync --chmod=Fugo=r -av #{files.join(' ')} #{dest}")

  examples = `git ls-files examples`.split("\n")
  sh("rsync --chmod=Fugo=r -av #{examples.join(' ')} #{dest}/examples/")
end

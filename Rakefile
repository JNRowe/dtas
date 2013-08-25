load "./GIT-VERSION-GEN"
manifest = "Manifest.txt"
gitidx = File.stat(".git/index") rescue nil
if ! File.exist?(manifest) || File.stat(manifest).mtime < gitidx.mtime
  system("git ls-files > #{manifest}")
  File.open(manifest, "a") do |fp|
    fp.puts "NEWS"
    fp.puts "lib/dtas/version.rb"

    if system("make -C Documentation")
      require 'fileutils'
      FileUtils.rm_rf 'man'
      if system("make -C Documentation gem-man")
        `git ls-files -o man`.split(/\n/).each do |man|
          fp.puts man
        end
      else
        warn "failed to install manpages for distribution"
      end
    else
      warn "failed to build manpages for distribution"
    end
  end
  File.open("NEWS", "w") do |fp|
    `git tag -l`.split(/\n/).each do |tag|
      %r{\Av([\d\.]+)} =~ tag or next
      version = $1
      header, subject, body = `git cat-file tag #{tag}`.split(/\n\n/, 3)
      header = header.split(/\n/)
      tagger = header.grep(/\Atagger /)[0]
      time = Time.at(tagger.split(/ /)[-2].to_i).utc
      date = time.strftime("%Y-%m-%d")

      fp.write("=== #{version} / #{date}\n\n#{subject}\n\n#{body}")
    end
    fp.flush
    if fp.size <= 5
      fp.puts "Unreleased"
    end
  end
end

require 'hoe'
Hoe.plugin :git
include Rake::DSL

h = Hoe.spec('dtas') do |p|
  developer 'Eric Wong', 'e@80x24.org'

  self.readme_file = 'README'
  self.history_file = 'NEWS'
  self.urls = %w(http://dtas.80x24.org/)
  self.summary = x = File.readlines("README")[0].split(/\s+/)[1].chomp
  self.description = self.paragraphs_of("README", 1)
  # no public APIs, no HTML, either
  self.need_rdoc = false
  self.extra_rdoc_files = []
  license "GPLv3+"
end

task :rsync_docs do
  dest = ENV["RSYNC_DEST"] || "80x24.org:/srv/dtas/"
  top = %w(INSTALL NEWS README COPYING)
  files = []
  Dir['Documentation/*.txt'].to_a.concat(top).each do |txt|
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
end

task :coverage do
  env = {
    "COVERAGE" => "1",
    "RUBYOPT" => "-r./test/helper",
  }
  File.open("coverage.dump", "w").close # clear
  pid = Process.spawn(env, "rake")
  _, status = Process.waitpid2(pid)
  require './test/covshow'
  exit status.exitstatus
end

base = "dtas-#{h.version}"
task tarball: "pkg/#{base}" do
  Dir.chdir("pkg") do
    tgz = "#{base}.tar.gz"
    tmp = "#{tmp}.#$$"
    sh "tar cf - #{base} | gzip -9 > #{tmp}"
    File.rename(tmp, tgz)
  end
end

task dist: [ :tarball, :package ] do
  Dir.chdir("pkg") do
    %w(dtas-linux dtas-mpris).each do |gem|
      sh "gem build ../#{gem}.gemspec"
    end
  end
end

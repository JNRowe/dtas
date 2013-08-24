load "./GIT-VERSION-GEN"
manifest = "Manifest.txt"
gitidx = File.stat(".git/index") rescue nil
if ! File.exist?(manifest) || File.stat(manifest).mtime < gitidx.mtime
  system("git ls-files > #{manifest}")
  File.open(manifest, "a") do |fp|
    fp.puts "NEWS"
    fp.puts "lib/dtas/version.rb"
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

Hoe.spec('dtas') do |p|
  developer 'Eric Wong', 'normalperson@yhbt.net'

  self.readme_file = 'README'
  self.history_file = 'NEWS'
  self.urls = %w(http://dtas.80x24.org/)
  self.summary = x = File.readlines("README")[0].split(/\s+/)[1].chomp
  self.description = self.paragraphs_of("README", 1)
  license "GPLv2+"

  dependency 'io_splice', '~> 4.2.0'
end

task :publish_docs do
  dest = "80x24.org:/srv/dtas/"
  system("rsync", "--files-from=.document", "-av", "#{Dir.pwd}/", dest)
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

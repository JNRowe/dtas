# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>.
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
# frozen_string_literal: true
require 'tempfile'
include Rake::DSL

def tags
  timefmt = '%Y-%m-%dT%H:%M:%SZ'
  @tags ||= `git tag -l --sort=-v:refname`.split(/\n/).map do |tag|
    if %r{\Av[\d\.]+} =~ tag
      header, subject, body = `git cat-file tag #{tag}`.split(/\n\n/, 3)
      header = header.split(/\n/)
      tagger = header.grep(/\Atagger /).first
      {
        time: Time.at(tagger.split(' ')[-2].to_i).utc.strftime(timefmt),
        tagger_name: %r{^tagger ([^<]+)}.match(tagger)[1].strip,
        tagger_email: %r{<([^>]+)>}.match(tagger)[1].strip,
        id: `git rev-parse refs/tags/#{tag}`.chomp!,
        tag: tag,
        subject: subject,
        body: body,
      }
    end
  end.compact.sort { |a,b| b[:time] <=> a[:time] }
end

task "NEWS" do
  latest = nil
  fp = Tempfile.new("NEWS", ".")
  fp.sync = true
  tags.each do |tag|
    version = tag[:tag].delete 'v'
    fp.puts "# #{version} / #{tag[:time].split('T')[0]}"
    fp.puts
    fp.puts tag[:subject]
    body = tag[:body]
    if body && body.strip.size > 0
      fp.puts "\n\n#{body}"
    end
    fp.puts
  end
  fp.puts "Unreleased" unless fp.size > 0
  fp.puts "# COPYRIGHT"
  fp.puts "Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>"
  fp.puts "License: GPL-3.0+ <http://www.gnu.org/licenses/gpl-3.0.txt>"
  fp.rewind
  assert_equal fp.read, File.read("NEWS") rescue nil
  fp.chmod 0644
  File.rename(fp.path, "NEWS")
end

desc 'prints news as an Atom feed'
task 'NEWS.atom' do
  require 'builder' # gem install builder
  url_base = 'http://dtas.80x24.org/'
  cgit_url = 'http://80x24.org/dtas.git/'
  new_tags = tags[0,10]
  x = Builder::XmlMarkup.new
  x.instruct! :xml, encoding: 'UTF-8', version: '1.0'
  x.feed(xmlns: 'http://www.w3.org/2005/Atom') do
    x.id "#{url_base}/NEWS.atom"
    x.title "dtas news"
    x.subtitle 'duct tape audio suite for *nix'
    x.link rel: 'alternate', type: 'text/plain', href: "#{url_base}/NEWS"
    x.updated(new_tags.empty? ? "1970-01-01T00:00:00Z" : new_tags.first[:time])
    new_tags.each do |tag|
      x.entry do
        x.title tag[:subject]
        x.updated tag[:time]
        x.published tag[:time]
        x.author {
          x.name tag[:tagger_name]
          x.email tag[:tagger_email]
        }
        url = "#{cgit_url}/tag/?id=#{tag[:tag]}"
        x.link rel: 'alternate', type: 'text/html', href: url
        x.id url
        x.content(type: :xhtml) do
          x.div(xmlns: 'http://www.w3.org/1999/xhtml') do
            x.pre tag[:body]
          end
        end
      end
    end
  end

  fp = Tempfile.new(%w(NEWS .atom), ".")
  fp.sync = true
  fp.puts x.target!
  fp.chmod 0644
  File.rename fp.path, 'NEWS.atom'
  fp.close!
end

task rsync_docs: %w(NEWS NEWS.atom) do
  dest = ENV["RSYNC_DEST"] || "80x24.org:/srv/dtas/"
  top = %w(INSTALL NEWS README COPYING NEWS.atom)
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

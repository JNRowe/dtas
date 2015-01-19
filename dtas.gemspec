# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
Gem::Specification.new do |s|
  manifest = File.read('.gem-manifest').split(/\n/)
  s.name = %q{dtas}
  s.version = ENV["VERSION"]
  s.authors = ["dtas hackers"]
  s.summary = "duct tape audio suite for *nix"
  s.description = File.read("README").split(/\n\n/)[1].strip
  s.email = %q{e@80x24.org}
  s.executables = manifest.grep(%r{\Abin/}).map { |s| s.sub(%r{\Abin/}, "") }
  s.files = manifest
  s.homepage = 'http://dtas.80x24.org/'
  s.licenses = "GPLv3+"
end

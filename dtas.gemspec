# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
Gem::Specification.new do |s|
  s.name = %q{dtas}
  s.version = ENV["VERSION"]
  s.authors = ["dtas hackers"]
  s.summary = "duct tape audio suite for *nix"
  s.description = File.read("README").split(/\n\n/)[1].strip
  s.email = %q{e@80x24.org}
  s.files = File.read('.gem-manifest').split(/\n/)
  s.homepage = 'http://dtas.80x24.org/'
  s.licenses = "GPLv3+"
end

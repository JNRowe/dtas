# Copyright 2013-2014, Eric Wong <e@80x24.org> and all contributors.
# License: GPLv2 or later <http://www.gnu.org/licenses/gpl-2.0.txt>
# This is GPLv2+ instead of GPLv3+ because ruby-dbus is LGPLv2.1 (only)
Gem::Specification.new do |s|
  s.name = %q{dtas-mpris}
  s.version = '0.0.0'
  s.authors = ["dtas hackers"]
  s.summary = "meta-package for the dtas-mpris proxy"
  s.description =
    "this allows controlling dtas-player via MPRIS or MPRIS 2.0\n" \
    "This is currently a dummy package as dtas-mpris is not implemented"
  s.email = %q{e@80x24.org}
  s.files = []
  s.homepage = 'http://dtas.80x24.org/'
  s.add_dependency(%q<dtas>)
  s.add_dependency(%q<ruby-dbus>)
  s.licenses = "GPLv2+"
end

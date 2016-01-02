# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-2.0+ or later <http://www.gnu.org/licenses/gpl-2.0.txt>
# This is GPL-2.0+ instead of GPL-3.0+ because ruby-dbus is LGPL-2.1 (only)
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
  s.licenses = 'GPL-2.0+'
end

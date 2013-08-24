# -*- encoding: binary -*-
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

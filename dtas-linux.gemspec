# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
#
# this just declares dependencies to make gem installation a little easier
# for Linux users
Gem::Specification.new do |s|
  s.name = %q{dtas-linux}
  s.version = '1.0.0'
  s.authors = ["dtas hackers"]
  s.summary = "meta-package for dtas users on the Linux kernel"
  s.description = "gives small performance improvements for dtas users\n" \
                  "via tee(), splice() and eventfd() on Linux"
  s.email = %q{e@80x24.org}
  s.files = []
  s.homepage = 'http://dtas.80x24.org/'
  s.add_dependency(%q<dtas>)
  s.add_dependency(%q<io_splice>, '~> 4')
  s.add_dependency(%q<sleepy_penguin>, '~> 3')
  s.licenses = 'GPL-3.0+'
end

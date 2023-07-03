# Copyright (C) 2013-2021 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
all::
pkg = dtas
RUBY = ruby
GIT-VERSION-FILE: .FORCE-GIT-VERSION-FILE
	@./GIT-VERSION-GEN
-include GIT-VERSION-FILE
lib := lib

all:: test
test_units := $(wildcard test/test_*.rb)
test: $(test_units)
$(test_units):
	$(RUBY) -w -I $(lib) $@ -v

check-warnings:
	@(for i in $$(git ls-files '*.rb'| grep -v '^setup\.rb$$'); \
	  do $(RUBY) -d -W2 -c $$i; done) | grep -v '^Syntax OK$$' || :

check: test
coverage: export COVERAGE=1
coverage:
	> coverage.dump
	$(MAKE) check
	$(RUBY) ./test/covshow.rb

pkggem := pkg/$(pkg)-$(VERSION).gem
pkgtgz := pkg/$(pkg)-$(VERSION).tar.gz

fix-perms:
	git ls-tree -r HEAD | awk '/^100644 / {print $$NF}' | xargs chmod 644
	git ls-tree -r HEAD | awk '/^100755 / {print $$NF}' | xargs chmod 755

gem: $(pkggem)

install-gem: $(pkggem)
	gem install --local $(CURDIR)/$<

$(pkggem): .gem-manifest
	VERSION=$(VERSION) gem build $(pkg).gemspec
	mkdir -p pkg
	mv $(@F) $@

pkg_extra := GIT-VERSION-FILE lib/dtas/version.rb NEWS
NEWS:
	rake -s $@
gem-man:
	-$(MAKE) -C Documentation/ gem-man
tgz-man:
	-$(MAKE) -C Documentation/ install-man mandir=$(CURDIR)/man
.PHONY: tgz-man gem-man

.gem-manifest: .manifest gem-man
	(ls man/*.?; cat .manifest) | LC_ALL=C sort > $@+
	cmp $@+ $@ || mv $@+ $@; rm -f $@+
.tgz-manifest: .manifest tgz-man
	(ls man/*/*; cat .manifest) | LC_ALL=C sort > $@+
	cmp $@+ $@ || mv $@+ $@; rm -f $@+
.manifest: NEWS fix-perms
	rm -rf man
	(git ls-files; \
	 for i in $(pkg_extra); do echo $$i; done) | \
	 LC_ALL=C sort > $@+
	cmp $@+ $@ || mv $@+ $@; rm -f $@+
$(pkgtgz): distdir = pkg/$(pkg)-$(VERSION)
$(pkgtgz): .tgz-manifest
	@test -n "$(distdir)"
	$(RM) -r $(distdir)
	mkdir -p $(distdir)
	tar cf - $$(cat .tgz-manifest) | (cd $(distdir) && tar xf -)
	cd pkg && tar cf - $(pkg)-$(VERSION) | gzip -9 > $(@F)+
	mv $@+ $@

package: $(pkgtgz) $(pkggem)

# Install symlinks to ~/bin (which is hopefuly in PATH) which point to
# this source tree.
# prefix + bindir matches git.git Makefile:
prefix = $(HOME)
bindir = $(prefix)/bin
symlink-install :
	mkdir -p $(bindir)
	dtas=$(CURDIR)/dtas.sh && cd $(bindir) && \
	for x in $(CURDIR)/bin/* $(CURDIR)/script/*; do \
		ln -sf "$$dtas" $$(basename "$$x"); \
	done

.PHONY: all .FORCE-GIT-VERSION-FILE test $(test_units) NEWS
.PHONY: check-warnings fix-perms

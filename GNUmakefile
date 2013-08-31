# Copyright (C) 2013, Eric Wong <normalperson@yhbt.net> and all contributors
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
all::

RUBY = ruby
GIT-VERSION-FILE: .FORCE-GIT-VERSION-FILE
	@./GIT-VERSION-GEN
-include GIT-VERSION-FILE
lib := lib

all:: test
test_units := $(wildcard test/test_*.rb)
test: test-unit
test-unit: $(test_units)
$(test_units):
	$(RUBY) -I $(lib) $@ $(RUBY_TEST_OPTS)

check-warnings:
	@(for i in $$(git ls-files '*.rb'| grep -v '^setup\.rb$$'); \
	  do $(RUBY) -d -W2 -c $$i; done) | grep -v '^Syntax OK$$' || :

check: test
coverage: export COVERAGE=1
coverage:
	> coverage.dump
	$(MAKE) check
	$(RUBY) ./test/covshow.rb

.PHONY: all .FORCE-GIT-VERSION-FILE test $(test_units)
.PHONY: check-warnings

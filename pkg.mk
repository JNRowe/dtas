RUBY = ruby
RAKE = rake
RSYNC = rsync

GIT-VERSION-FILE: .FORCE-GIT-VERSION-FILE
	@./GIT-VERSION-GEN
-include GIT-VERSION-FILE
-include local.mk
DLEXT := $(shell $(RUBY) -rrbconfig -e 'puts RbConfig::CONFIG["DLEXT"]')
RUBY_VERSION := $(shell $(RUBY) -e 'puts RUBY_VERSION')
RUBY_ENGINE := $(shell $(RUBY) -e 'puts((RUBY_ENGINE rescue "ruby"))')
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

.PHONY: all .FORCE-GIT-VERSION-FILE test $(test_units)
.PHONY: check-warnings

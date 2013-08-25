all::
include pkg.mk

check: test
coverage: export COVERAGE=1
coverage:
	> coverage.dump
	$(MAKE) check
	$(RUBY) ./test/covshow.rb

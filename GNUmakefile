all::
RSYNC_DEST := 80x24.org:/srv/dtas/
rfproject := dtas
rfpackage := dtas
include pkg.mk

check: test
coverage: export COVERAGE=1
coverage:
	> coverage.dump
	$(MAKE) check
	$(RUBY) ./test/covshow.rb

RSYNC = rsync --exclude '*.html' --exclude '*.html.gz' \
        --exclude images --exclude '*.css' --exclude '*.css.gz' \
	--exclude created.* \
	--exclude '*.ri' --exclude '*.ri.gz' --exclude ri

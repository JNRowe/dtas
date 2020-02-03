# Copyright (C) 2013-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
all::

INSTALL = install
POD2MAN = pod2man
-include ../GIT-VERSION-FILE
release := dtas $(VERSION)
POD2MAN_OPTS = -v -r '$(release)' --stderr -d 1994-10-02 -c 'dtas user manual'
pod2man = $(POD2MAN) $(POD2MAN_OPTS)
POD2TEXT = pod2text
POD2TEXT_OPTS = --stderr
pod2text = $(POD2TEXT) $(POD2TEXT_OPTS)

m1 =
m1 += dtas-console
m1 += dtas-cueedit
m1 += dtas-ctl
m1 += dtas-enq
m1 += dtas-msinkctl
m1 += dtas-player
m1 += dtas-xdelay
m1 += dtas-sinkedit
m1 += dtas-sourceedit
m1 += dtas-tl
m1 += dtas-splitfx
m1 += dtas-archive

m7 =
m7 += dtas-player_protocol
m7 += dtas-player_sink_examples
m7 += dtas-player_effects
m7 += dtas-env

man1 := $(addsuffix .1, $(m1))
man7 := $(addsuffix .7, $(m7))

all:: man

man: $(man1) $(man7)

prefix ?= $(HOME)
mandir ?= $(prefix)/share/man
man1dir = $(mandir)/man1
man7dir = $(mandir)/man7

gem-man: man
	$(INSTALL) -d -m 755 ../man
	$(INSTALL) -m 644 $(man1) ../man
	$(INSTALL) -m 644 $(man7) ../man

install-man: man
	$(INSTALL) -d -m 755 $(DESTDIR)$(man1dir)
	$(INSTALL) -d -m 755 $(DESTDIR)$(man7dir)
	$(INSTALL) -m 644 $(man1) $(DESTDIR)$(man1dir)
	$(INSTALL) -m 644 $(man7) $(DESTDIR)$(man7dir)

%.1 : %.pod
	$(pod2man) -s 1 $< $@+ && mv $@+ $@

%.7 : %.pod
	$(pod2man) -s 7 $< $@+ && mv $@+ $@

mantxt = $(addsuffix .txt, $(m1) $(m7))

txt :: $(mantxt)

all :: txt

%.txt : %.pod
	$(pod2text) $< $@+
	touch -r $< $@+
	mv $@+ $@

clean::
	$(RM) $(man1) $(man7)
	$(RM) $(addsuffix .txt.gz, $(m1) $(m7))

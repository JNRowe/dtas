all::

PANDOC = pandoc
PANDOC_OPTS = -f markdown --email-obfuscation=none
pandoc = $(PANDOC) $(PANDOC_OPTS)

ones =
ones += dtas-console
ones += dtas-ctl
ones += dtas-enq
ones += dtas-msinkctl
ones += dtas-player
ones += dtas-xdelay
ones += dtas-sinkedit
ones += dtas-sourceedit

man1 := $(addsuffix .1, $(ones))
man7 := $(addsuffix .7,dtas-player_protocol)

all:: man

man: $(man1) $(man7)

prefix?=$(HOME)
mandir?=$(prefix)/share/man
man1dir=$(mandir)/man1
man5dir=$(mandir)/man5
man7dir=$(mandir)/man7

INSTALL = install

gem-man: man
	$(INSTALL) -d -m 755 ../man
	$(INSTALL) -m 644 $(man1) ../man
	$(INSTALL) -m 644 $(man7) ../man

install-man: man
	$(INSTALL) -d -m 755 $(DESTDIR)$(man1dir)
	$(INSTALL) -d -m 755 $(DESTDIR)$(man7dir)
	$(INSTALL) -m 644 $(man1) $(DESTDIR)$(man1dir)
	$(INSTALL) -m 644 $(man7) $(DESTDIR)$(man7dir)
%.1 %.7 : %.txt
	$(pandoc) -s -t man < $< > $@+ && mv $@+ $@

clean::
	$(RM) $(man1) $(man7)

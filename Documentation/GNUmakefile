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

install-man: man
	mkdir -p ../man/man1
	mkdir -p ../man/man7
	install -m 644 $(man1) ../man/man1
	install -m 644 $(man7) ../man/man7

%.1: %.1.txt
	$(pandoc) -s -t man < $< > $@+ && mv $@+ $@
%.7: %.7.txt
	$(pandoc) -s -t man < $< > $@+ && mv $@+ $@

clean::
	$(RM) $(man1)

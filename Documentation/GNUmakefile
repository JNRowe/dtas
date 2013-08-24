all::

PANDOC = pandoc
PANDOC_OPTS = -f markdown --email-obfuscation=none
pandoc = $(PANDOC) $(PANDOC_OPTS)

man1 := $(addsuffix .1,dtas-enq)
man7 := $(addsuffix .7,dtas-player_protocol)

all:: man

man: $(man1) $(man7)

install-man: man
	mkdir -p ../man/man1
	install -m 644 $(man1) ../man/man1

%.1: %.1.txt
	$(pandoc) -s -t man < $< > $@+ && mv $@+ $@
%.7: %.7.txt
	$(pandoc) -s -t man < $< > $@+ && mv $@+ $@

clean::
	$(RM) $(man1)

PHONY = install uninstall test

ifeq ($(PREFIX), )
	PREFIX = /usr
endif

all:

clean:

test:

install:
	mkdir -p $(DESTDIR)/$(PREFIX)/bin
	mkdir -p $(DESTDIR)/$(PREFIX)/share/toolbox/utils
	install -o root -g root -m 755 src/dstatus.sh $(DESTDIR)/$(PREFIX)/share/toolbox/utils/.
	ln -s $(PREFIX)/share/toolbox/utils/dstatus.sh $(DESTDIR)/$(PREFIX)/bin/dstatus

uninstall:
	rm $(DESTDIR)/$(PREFIX)/bin/dstatus
	rm $(DESTDIR)/$(PREFIX)/share/toolbox/utils/dstatus.sh

.PHONY: $(PHONY)

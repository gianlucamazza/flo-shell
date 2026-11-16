# flo-shell: install the shell, the greeter and the session files.
#
#   make install DESTDIR=/tmp/pkg PREFIX=/usr
#
# Nothing is compiled. Layout:
#   $(DATADIR)/shell      Quickshell configuration of the shell
#   $(DATADIR)/greeter    Quickshell configuration of the greeter (symlinks
#                         into ../shell for everything it shares)
#   $(DATADIR)/session    Hyprland configurations
#   $(BINDIR)             flo-shell, flo-session
#   $(SESSIONDIR)         flo-shell.desktop
#   $(SYSCONFDIR)/pam.d   PAM service of the lock screen
#   $(DOCDIR)             greetd configuration example

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/flo-shell
SESSIONDIR ?= $(PREFIX)/share/wayland-sessions
DOCDIR ?= $(PREFIX)/share/doc/flo-shell
SYSCONFDIR ?= /etc
USERUNITDIR ?= $(PREFIX)/lib/systemd/user

SCRIPTS = flo-shell flo-session flo-hyprland
GREETER_LINKS = Device.qml Theme.qml I18n.qml components lock services

all: $(addprefix build/,$(SCRIPTS))

build/%: session/%.in
	mkdir -p build
	sed 's|@DATADIR@|$(DATADIR)|g' $< > $@

check: all
	sh -n build/flo-shell
	sh -n build/flo-session
	sh -n build/flo-hyprland
	sh -n dev/run-nested.sh
	python3 dev/test-hyprland-launcher.py
	python3 dev/test-brightness.py
	sh dev/check-hyprland.sh

install: all
	mkdir -p $(DESTDIR)$(DATADIR)/shell $(DESTDIR)$(DATADIR)/greeter $(DESTDIR)$(DATADIR)/session
	cp -R shell/. $(DESTDIR)$(DATADIR)/shell/
	install -m 644 greeter/shell.qml greeter/Greeter.qml $(DESTDIR)$(DATADIR)/greeter/
	for f in $(GREETER_LINKS); do ln -sfn ../shell/$$f $(DESTDIR)$(DATADIR)/greeter/$$f; done
	install -m 644 session/hyprland.conf session/greeter-hyprland.conf session/hyprland.lua session/greeter-hyprland.lua $(DESTDIR)$(DATADIR)/session/
	mkdir -p $(DESTDIR)$(DATADIR)/xdg/applications
	install -m 644 session/xdg/applications/*.desktop $(DESTDIR)$(DATADIR)/xdg/applications/
	find $(DESTDIR)$(DATADIR) -type d -exec chmod 755 {} +
	find $(DESTDIR)$(DATADIR) -type f -exec chmod 644 {} +
	mkdir -p $(DESTDIR)$(BINDIR) $(DESTDIR)$(SESSIONDIR) $(DESTDIR)$(SYSCONFDIR)/pam.d $(DESTDIR)$(DOCDIR)
	install -m 755 $(addprefix build/,$(SCRIPTS)) $(DESTDIR)$(BINDIR)/
	install -m 644 session/flo-shell.desktop $(DESTDIR)$(SESSIONDIR)/
	mkdir -p $(DESTDIR)$(USERUNITDIR)
	install -m 644 session/flo-shell-session.target $(DESTDIR)$(USERUNITDIR)/
	install -m 644 session/pam/flo-shell $(DESTDIR)$(SYSCONFDIR)/pam.d/flo-shell
	install -m 644 session/greetd/config.toml $(DESTDIR)$(DOCDIR)/greetd-config.toml

uninstall:
	rm -rf $(DESTDIR)$(DATADIR) $(DESTDIR)$(DOCDIR)
	rm -f $(addprefix $(DESTDIR)$(BINDIR)/,$(SCRIPTS))
	rm -f $(DESTDIR)$(USERUNITDIR)/flo-shell-session.target
	rm -f $(DESTDIR)$(SESSIONDIR)/flo-shell.desktop $(DESTDIR)$(SYSCONFDIR)/pam.d/flo-shell

clean:
	rm -rf build

.PHONY: all check install uninstall clean

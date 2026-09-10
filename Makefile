CC ?= clang
CFLAGS ?= -fobjc-arc -Wall -Wextra -O2
LDFLAGS ?= -framework Cocoa -framework UniformTypeIdentifiers
VERSION ?= 1.0
APP_NAME ?= ClassBar
BUNDLE_ID ?= local.classbar
SIGN_IDENTITY ?= -
PREFIX ?= $(HOME)/Applications

APP := $(PREFIX)/$(APP_NAME).app
EXEC := $(APP)/Contents/MacOS/$(APP_NAME)
AGENT := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
CONFIG_DIR := $(HOME)/Library/Application Support/classbar
UID := $(shell id -u)

.PHONY: all test app install uninstall config run clean

all: classbar

classbar: main.m icons.h
	$(CC) $(CFLAGS) $(LDFLAGS) main.m -o $@

cbtest: main.m icons.h
	$(CC) $(CFLAGS) -DCLASSBAR_TEST $(LDFLAGS) main.m -o $@

test: cbtest
	./cbtest

run: classbar
	./classbar

app: classbar
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	sed -e 's|@APP_NAME@|$(APP_NAME)|g' \
	    -e 's|@BUNDLE_ID@|$(BUNDLE_ID)|g' \
	    -e 's|@VERSION@|$(VERSION)|g' \
	    packaging/Info.plist.in > "$(APP)/Contents/Info.plist"
	cp classbar "$(EXEC)"
	codesign -s $(SIGN_IDENTITY) --force "$(APP)"

install: app
	mkdir -p "$(HOME)/Library/LaunchAgents"
	sed -e 's|@BUNDLE_ID@|$(BUNDLE_ID)|g' \
	    -e 's|@EXEC_PATH@|$(EXEC)|g' \
	    packaging/agent.plist.in > "$(AGENT)"
	launchctl bootout gui/$(UID)/$(BUNDLE_ID) 2>/dev/null || true
	launchctl bootstrap gui/$(UID) "$(AGENT)"
	launchctl kickstart -k gui/$(UID)/$(BUNDLE_ID)
	@echo "installed $(APP) as $(BUNDLE_ID)"

config:
	mkdir -p "$(CONFIG_DIR)"
	@if [ -f "$(CONFIG_DIR)/schedule.json" ]; then \
	  echo "kept existing $(CONFIG_DIR)/schedule.json"; \
	else \
	  cp schedule.example.json "$(CONFIG_DIR)/schedule.json"; \
	  echo "wrote $(CONFIG_DIR)/schedule.json from the example"; \
	fi

uninstall:
	launchctl bootout gui/$(UID)/$(BUNDLE_ID) 2>/dev/null || true
	rm -f "$(AGENT)"
	rm -rf "$(APP)"
	@echo "removed $(APP) and $(BUNDLE_ID)"

clean:
	rm -rf classbar cbtest *.dSYM

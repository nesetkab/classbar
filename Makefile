CC ?= clang
ARCHS ?= -arch arm64 -arch x86_64
CFLAGS ?= -fobjc-arc -Wall -Wextra -O2 -mmacosx-version-min=13.0 $(ARCHS)
LDFLAGS ?= -framework Cocoa -framework UniformTypeIdentifiers
VERSION ?= 1.0
APP_NAME ?= ClassBar
BUNDLE_ID ?= local.classbar
SIGN_IDENTITY ?= -
PREFIX ?= $(HOME)/Applications

BUILD := build
LIB := $(addprefix src/,icons.m store.m schedule.m ics.m views.m settings.m app.m)
HEADERS := $(wildcard src/*.h)

BIN := $(BUILD)/classbar
TESTBIN := $(BUILD)/cbtest
BUNDLE := $(BUILD)/$(APP_NAME).app
ZIP := $(BUILD)/$(APP_NAME).zip

APP := $(PREFIX)/$(APP_NAME).app
EXEC := $(APP)/Contents/MacOS/$(APP_NAME)
AGENT := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
CONFIG_DIR := $(HOME)/Library/Application Support/classbar
UID := $(shell id -u)

.PHONY: all test app dist install uninstall config run clean

all: $(BIN)

$(BUILD):
	mkdir -p $@

$(BIN): $(LIB) src/main.m $(HEADERS) | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) $(LIB) src/main.m -o $@

$(TESTBIN): $(LIB) tests/tests.m $(HEADERS) | $(BUILD)
	$(CC) $(CFLAGS) -Isrc $(LDFLAGS) $(LIB) tests/tests.m -o $@

test: $(TESTBIN)
	./$(TESTBIN)

run: $(BIN)
	./$(BIN)

app: $(BIN)
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	sed -e 's|@APP_NAME@|$(APP_NAME)|g' \
	    -e 's|@BUNDLE_ID@|$(BUNDLE_ID)|g' \
	    -e 's|@VERSION@|$(VERSION)|g' \
	    packaging/Info.plist.in > "$(BUNDLE)/Contents/Info.plist"
	cp $(BIN) "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	codesign -s $(SIGN_IDENTITY) --force "$(BUNDLE)"

dist: app
	rm -f "$(ZIP)"
	cd $(BUILD) && ditto -c -k --keepParent "$(APP_NAME).app" "$(APP_NAME).zip"
	@echo "wrote $(ZIP)"

install: app
	mkdir -p "$(PREFIX)" "$(HOME)/Library/LaunchAgents"
	rm -rf "$(APP)"
	ditto "$(BUNDLE)" "$(APP)"
	sed -e 's|@BUNDLE_ID@|$(BUNDLE_ID)|g' \
	    -e 's|@EXEC_PATH@|$(EXEC)|g' \
	    packaging/agent.plist.in > "$(AGENT)"
	launchctl bootout gui/$(UID)/$(BUNDLE_ID) 2>/dev/null || true
	launchctl bootstrap gui/$(UID) "$(AGENT)" 2>/dev/null || \
	  (sleep 1; launchctl bootstrap gui/$(UID) "$(AGENT)")
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
	rm -rf $(BUILD)

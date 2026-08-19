APP        := WineWatch
CONFIG     ?= release
ARCHS      ?= arm64
ARCH_FLAGS := $(foreach a,$(ARCHS),--arch $(a))
SWIFT_ARGS := -c $(CONFIG) $(ARCH_FLAGS)

DIST     := .dist
APP_DIR  := $(DIST)/$(APP).app
CONTENTS := $(APP_DIR)/Contents
BIN_PATH  = $(shell swift build $(SWIFT_ARGS) --show-bin-path)
INSTALL_DIR ?= /Applications

.PHONY: all app build universal run install uninstall list preview clean

all: app

build:
	swift build $(SWIFT_ARGS)

## Assemble a launchable, ad-hoc signed WineWatch.app in .dist/
app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BIN_PATH)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@rm -rf "$(DIST)/AppIcon.iconset"
	@"$(BIN_PATH)/$(APP)" --export-icon "$(DIST)/AppIcon.iconset" \
		&& iconutil -c icns "$(DIST)/AppIcon.iconset" -o "$(CONTENTS)/Resources/AppIcon.icns" \
		|| echo "note: app icon generation skipped"
	codesign --force --sign - --timestamp=none "$(APP_DIR)" >/dev/null 2>&1 \
		|| echo "note: ad-hoc signing failed; launch-at-login may not work"
	@echo "built $(APP_DIR)"

## Intel + Apple Silicon
universal:
	$(MAKE) app ARCHS="arm64 x86_64"

## Replace any running copy and launch from .dist/
run: app
	-pkill -x $(APP) 2>/dev/null || true
	open "$(APP_DIR)"

## Install into /Applications (required for Launch at Startup to stick)
install: app
	-pkill -x $(APP) 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/$(APP).app"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(APP).app"
	open "$(INSTALL_DIR)/$(APP).app"
	@echo "installed to $(INSTALL_DIR)/$(APP).app"

uninstall:
	-pkill -x $(APP) 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/$(APP).app"

## Print what WineWatch would count, without running the UI
list: build
	@"$(BIN_PATH)/$(APP)" --list

## Render the status icon at 10x for eyeballing
preview: build
	@"$(BIN_PATH)/$(APP)" --preview "$(DIST)/preview.png" 10 && open "$(DIST)/preview.png"

clean:
	rm -rf .build $(DIST)

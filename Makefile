.PHONY: gen open build test lint screenshot screenshot-ios clean archive export dmg install reinstall

PROJECT := Cairn.xcodeproj
SCHEME  := Cairn
VERSION ?= 0.1.0
BUILD_DIR := build
ARCHIVE_PATH := $(BUILD_DIR)/Cairn.xcarchive
EXPORT_PATH  := $(BUILD_DIR)/export
DMG_PATH     := $(BUILD_DIR)/Cairn-$(VERSION).dmg

# Default build / test runs on macOS so it works without an iOS SDK installed and
# without a real signing team. The app is ad-hoc signed while keeping the shipped
# sandbox, network-client, and user-selected-file entitlements intact.
LOCAL_XCFLAGS := \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGN_STYLE=Manual \
	DEVELOPMENT_TEAM=""

DESTINATION ?= platform=macOS,arch=arm64

# Per-checkout DerivedData keeps parallel git worktrees from sharing build state.
DERIVED_DATA ?= $(BUILD_DIR)/DerivedData
# Keep errors, warnings, test counts, and the final status line. LOG_FILTER=cat shows full logs.
LOG_FILTER ?= grep -E ': (error|warning): |Executed [0-9]+ tests?|\*\* [A-Z ]+ \*\*'
# Focused tests: make test ONLY=CairnTests/SnapshotServiceTests
ONLY ?=
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-derivedDataPath $(DERIVED_DATA)

gen:
	xcodegen generate

open: gen
	open $(PROJECT)

build: gen
	set -o pipefail; $(XCODEBUILD) \
		-destination '$(DESTINATION)' -configuration Debug \
		$(LOCAL_XCFLAGS) build | $(LOG_FILTER)

test: gen
	set -o pipefail; $(XCODEBUILD) \
		-destination '$(DESTINATION)' -configuration Debug \
		-enableCodeCoverage NO $(if $(ONLY),-only-testing:$(ONLY)) \
		$(LOCAL_XCFLAGS) test | $(LOG_FILTER)

lint:
	swiftlint lint

# Debug-only: launch with in-memory sample data and capture the window.
# make screenshot SCREEN=assets LANG_CODE=zh-Hans APPEARANCE=dark OUT=build/screenshots/assets.png
screenshot: build
	SCREEN="$(SCREEN)" LANG_CODE="$(LANG_CODE)" APPEARANCE="$(APPEARANCE)" OUT="$(OUT)" \
		scripts/screenshot-macos.sh

# Same as screenshot, on a simulator (default: the booted one). Set DEVICE=<udid> to pick one.
screenshot-ios: gen
	$(MAKE) build DESTINATION='generic/platform=iOS Simulator'
	DEVICE="$(DEVICE)" SCREEN="$(SCREEN)" LANG_CODE="$(LANG_CODE)" APPEARANCE="$(APPEARANCE)" OUT="$(OUT)" \
		scripts/screenshot-ios.sh

clean:
	rm -rf build DerivedData $(PROJECT)

archive: gen
	mkdir -p $(BUILD_DIR)
	set -o pipefail; $(XCODEBUILD) \
		-configuration Release -destination 'generic/platform=macOS' \
		-archivePath $(ARCHIVE_PATH) \
		$(LOCAL_XCFLAGS) archive | $(LOG_FILTER)

export: archive
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>method</key><string>mac-application</string>' \
		'<key>signingStyle</key><string>manual</string>' \
		'</dict></plist>' > $(BUILD_DIR)/ExportOptions.plist
	rm -rf $(EXPORT_PATH)
	xcodebuild -exportArchive -archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_PATH) \
		-exportOptionsPlist $(BUILD_DIR)/ExportOptions.plist

dmg: export
	rm -rf $(BUILD_DIR)/dmg-stage
	mkdir -p $(BUILD_DIR)/dmg-stage
	cp -R $(EXPORT_PATH)/Cairn.app $(BUILD_DIR)/dmg-stage/
	ln -s /Applications $(BUILD_DIR)/dmg-stage/Applications
	rm -f $(DMG_PATH)
	hdiutil create -volname "Cairn" -srcfolder $(BUILD_DIR)/dmg-stage \
		-ov -format UDZO $(DMG_PATH)
	@echo "DMG => $(DMG_PATH)"

# Local-only: kill any running Cairn instance and replace
# /Applications/Cairn.app with the freshly exported build.
install: export
	@echo "Stopping running Cairn instances…"
	-@osascript -e 'tell application "Cairn" to quit' >/dev/null 2>&1 || true
	-@pkill -x Cairn >/dev/null 2>&1 || true
	@for i in 1 2 3 4 5; do \
		pgrep -x Cairn >/dev/null 2>&1 || break; \
		sleep 0.3; \
	done
	-@pkill -9 -x Cairn >/dev/null 2>&1 || true
	@echo "Installing $(EXPORT_PATH)/Cairn.app to /Applications…"
	rm -rf /Applications/Cairn.app
	cp -R $(EXPORT_PATH)/Cairn.app /Applications/Cairn.app
	@xattr -dr com.apple.quarantine /Applications/Cairn.app 2>/dev/null || true
	@echo "Launching Cairn…"
	open -a /Applications/Cairn.app

# Convenience alias.
reinstall: install

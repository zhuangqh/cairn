.PHONY: gen open build test lint clean archive export dmg install reinstall

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

gen:
	xcodegen generate

open: gen
	open $(PROJECT)

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		$(LOCAL_XCFLAGS) build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		-enableCodeCoverage NO \
		$(LOCAL_XCFLAGS) test

lint:
	swiftlint lint

clean:
	rm -rf build DerivedData $(PROJECT)

archive: gen
	mkdir -p $(BUILD_DIR)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -destination 'generic/platform=macOS' \
		-archivePath $(ARCHIVE_PATH) \
		$(LOCAL_XCFLAGS) archive

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

.PHONY: gen open build test lint clean archive export dmg

PROJECT := Cairn.xcodeproj
SCHEME  := Cairn
VERSION ?= 0.1.0
BUILD_DIR := build
ARCHIVE_PATH := $(BUILD_DIR)/Cairn.xcarchive
EXPORT_PATH  := $(BUILD_DIR)/export
DMG_PATH     := $(BUILD_DIR)/Cairn-$(VERSION).dmg

# Default build / test runs on macOS so it works without an iOS SDK installed and
# without a real signing team. Entitlements that require a provisioning profile
# (CloudKit, APS) are stripped for local verification; Xcode restores them
# automatically when a developer opens the project with their Team ID.
LOCAL_XCFLAGS := \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGN_STYLE=Manual \
	DEVELOPMENT_TEAM="" \
	CODE_SIGN_ENTITLEMENTS=""

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
		$(LOCAL_XCFLAGS) test

lint:
	swiftlint lint --strict

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

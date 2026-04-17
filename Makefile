.PHONY: gen open build test lint clean

PROJECT := Cairn.xcodeproj
SCHEME  := Cairn

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

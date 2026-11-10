#!/bin/sh
# Install the Debug iOS Simulator build, launch it with the mock dataset loaded
# into an in-memory store, and capture the simulator screen. Run through
# `make screenshot-ios`.
#
# Environment:
#   DEVICE      simulator UDID or "booted"                 (default: booted)
#   SCREEN      dashboard | assets | accounts | settings   (default: dashboard)
#   LANG_CODE   en | zh-Hans                               (default: en)
#   APPEARANCE  light | dark                               (default: light)
#   OUT         output PNG path       (default: build/screenshots/ios-<screen>-<lang>-<appearance>.png)
#   DELAY       seconds to wait after launch               (default: 3)
#   MOCK_DATA   Cairn backup to load            (default: example/cairn-mock-data.json)
#
# Home currency is pinned to USD to match the mock dataset.
# The simulator's installed Cairn bundle is replaced, but its data container is
# untouched: sample data is in memory and settings come from launch arguments.
set -eu

cd "$(dirname "$0")/.."

APP="${APP:-build/DerivedData/Build/Products/Debug-iphonesimulator/Cairn.app}"
BUNDLE_ID="com.zhuangqh.cairn"
DEVICE="${DEVICE:-booted}"
SCREEN="${SCREEN:-dashboard}"
LANG_CODE="${LANG_CODE:-en}"
APPEARANCE="${APPEARANCE:-light}"
DELAY="${DELAY:-3}"
OUT="${OUT:-build/screenshots/ios-$SCREEN-$LANG_CODE-$APPEARANCE.png}"
MOCK_DATA="${MOCK_DATA:-example/cairn-mock-data.json}"

case "$LANG_CODE" in
    en) LANGUAGE_OVERRIDE=english ;;
    zh-Hans) LANGUAGE_OVERRIDE=simplifiedChinese ;;
    *) echo "Unsupported LANG_CODE: $LANG_CODE" >&2; exit 64 ;;
esac

if [ ! -d "$APP" ]; then
    echo "Missing $APP; run 'make screenshot-ios' first." >&2
    exit 66
fi

if [ ! -f "$MOCK_DATA" ]; then
    echo "Missing mock data $MOCK_DATA." >&2
    exit 66
fi
# The simulator app reads the host file directly, so pass an absolute path.
case "$MOCK_DATA" in /*) ;; *) MOCK_DATA="$PWD/$MOCK_DATA" ;; esac

mkdir -p "$(dirname "$OUT")"

xcrun simctl install "$DEVICE" "$APP"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
    -CairnMockData "$MOCK_DATA" \
    -CairnScreen "$SCREEN" \
    -cairn.onboardingCompleted YES \
    -cairn.featureTourSeen YES \
    -cairn.homeCurrency USD \
    -cairn.languageOverride "$LANGUAGE_OVERRIDE" \
    -cairn.appearance "$APPEARANCE" \
    -AppleLanguages "($LANG_CODE)" \
    >/dev/null
trap 'xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true' EXIT INT TERM

sleep "$DELAY"
xcrun simctl io "$DEVICE" screenshot "$OUT" >/dev/null 2>&1
echo "$OUT"

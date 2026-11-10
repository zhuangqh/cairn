#!/bin/sh
# Launch the Debug macOS build with the mock dataset loaded into an in-memory
# store and capture its window. Run through `make screenshot` so the app is
# built first.
#
# Environment:
#   SCREEN      dashboard | assets | accounts | settings   (default: dashboard)
#   LANG_CODE   en | zh-Hans                               (default: en)
#   APPEARANCE  light | dark                               (default: light)
#   OUT         output PNG path       (default: build/screenshots/<screen>-<lang>-<appearance>.png)
#   DELAY       seconds to wait after the window appears   (default: 2)
#   MOCK_DATA   Cairn backup to load            (default: example/cairn-mock-data.json)
#
# Home currency is pinned to USD to match the mock dataset.
# Settings are passed through the launch-argument defaults domain, so they are
# read for this launch only; model data lives in memory and is discarded.
# The sandboxed app can only read inside its container, so the mock file is
# staged in the container's tmp directory for this run and removed afterwards.
set -eu

cd "$(dirname "$0")/.."

APP="${APP:-build/DerivedData/Build/Products/Debug/Cairn.app}"
SCREEN="${SCREEN:-dashboard}"
LANG_CODE="${LANG_CODE:-en}"
APPEARANCE="${APPEARANCE:-light}"
DELAY="${DELAY:-2}"
OUT="${OUT:-build/screenshots/$SCREEN-$LANG_CODE-$APPEARANCE.png}"
MOCK_DATA="${MOCK_DATA:-example/cairn-mock-data.json}"
CONTAINER_TMP="$HOME/Library/Containers/com.zhuangqh.cairn/Data/tmp"

case "$LANG_CODE" in
    en) LANGUAGE_OVERRIDE=english ;;
    zh-Hans) LANGUAGE_OVERRIDE=simplifiedChinese ;;
    *) echo "Unsupported LANG_CODE: $LANG_CODE" >&2; exit 64 ;;
esac

if [ ! -x "$APP/Contents/MacOS/Cairn" ]; then
    echo "Missing $APP; run 'make screenshot' or 'make build' first." >&2
    exit 66
fi

if [ ! -f "$MOCK_DATA" ]; then
    echo "Missing mock data $MOCK_DATA." >&2
    exit 66
fi
if [ ! -d "$CONTAINER_TMP" ]; then
    echo "Missing $CONTAINER_TMP; launch Cairn once so macOS creates its container." >&2
    exit 66
fi

mkdir -p "$(dirname "$OUT")"

case "$APP" in /*) ;; *) APP="$PWD/$APP" ;; esac
EXECUTABLE="$APP/Contents/MacOS/Cairn"
if pgrep -f "^$EXECUTABLE" >/dev/null 2>&1; then
    echo "A Cairn instance from $APP is already running; quit it first." >&2
    exit 1
fi

STAGED_MOCK="$CONTAINER_TMP/cairn-screenshot-mock-$$.json"
cp "$MOCK_DATA" "$STAGED_MOCK"
trap 'rm -f "$STAGED_MOCK"' EXIT INT TERM

# Launch through LaunchServices; a directly executed binary gets no window.
open -n "$APP" --args \
    -CairnMockData "$STAGED_MOCK" \
    -CairnScreen "$SCREEN" \
    -cairn.onboardingCompleted YES \
    -cairn.featureTourSeen YES \
    -cairn.homeCurrency USD \
    -cairn.languageOverride "$LANGUAGE_OVERRIDE" \
    -cairn.appearance "$APPEARANCE" \
    -AppleLanguages "($LANG_CODE)"

PID=""
for _ in $(seq 1 20); do
    PID="$(pgrep -nf "^$EXECUTABLE" || true)"
    [ -n "$PID" ] && break
    sleep 0.5
done
if [ -z "$PID" ]; then
    echo "Cairn did not launch." >&2
    exit 1
fi
trap 'kill "$PID" 2>/dev/null || true; rm -f "$STAGED_MOCK"' EXIT INT TERM

# A launch without user interaction may finish with no window; a reopen event
# (as from a Dock click) makes the WindowGroup create one.
sleep 2
open "$APP"

WINDOW_ID=""
for _ in $(seq 1 40); do
    WINDOW_ID="$(xcrun swift scripts/window-id.swift "$PID" 2>/dev/null || true)"
    [ -n "$WINDOW_ID" ] && break
    sleep 0.5
done

if [ -z "$WINDOW_ID" ]; then
    echo "Cairn window did not appear." >&2
    exit 1
fi

sleep "$DELAY"
screencapture -o -x -l "$WINDOW_ID" "$OUT"
echo "$OUT"

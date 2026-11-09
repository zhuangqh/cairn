#!/bin/sh
# PostToolUse hook: lint an edited Swift file and report violations to Claude.
# Skips silently when SwiftLint is not installed; `make lint` remains the gate.
set -u

command -v swiftlint >/dev/null 2>&1 || exit 0

FILE="$(jq -r '.tool_input.file_path // empty')"
case "$FILE" in
    *.swift) ;;
    *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
if ! OUTPUT="$(swiftlint lint --quiet "$FILE" 2>&1)"; then
    printf 'SwiftLint errors in %s:\n%s\n' "$FILE" "$OUTPUT" >&2
    exit 2
fi

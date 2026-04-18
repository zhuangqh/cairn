# Cairn

A family asset-management app for Apple platforms (macOS first).
See [PRD.md](PRD.md) for the full product spec.

> The name comes from mountaineering — a cairn is a stack of stones left as a trail marker.
> Each monthly snapshot in the app is one more stone on your financial trail.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

## Status

Early-stage. macOS is the primary target. iOS / iPadOS sources still build but are not tested
for distribution — Cairn has no Apple Developer account behind it, so there are no signed
iOS builds and CloudKit sync is intentionally not used.

Data lives locally in the sandboxed Application Support directory. Use
**Settings → Backup → Export** to produce a `.cairn` JSON file that you can drop into
iCloud Drive / Dropbox / Git to carry between Macs.

## Prerequisites

- macOS 14+ and Xcode 15.3+ (Swift 5.10+, SwiftData)
- Homebrew packages: `xcodegen`, `swiftlint`
  ```sh
  brew install xcodegen swiftlint
  ```

No Apple Developer account is required for local builds. The shipped entitlements are
sandbox + user-selected files only, and the Makefile signs with an ad-hoc identity.

## Build & Run

The Xcode project is **not** committed — it is regenerated from [`project.yml`](project.yml)
via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make gen          # generate Cairn.xcodeproj
make open         # generate + open in Xcode
make build        # xcodebuild for macOS (ad-hoc signed)
make test         # run unit tests
make lint         # run SwiftLint (incl. i18n custom rules)
make clean        # wipe project + build artifacts
```

## Structure

```
Cairn/
├─ App/          # CairnApp, RootView, tab container
├─ Features/     # Overview / Accounts / Snapshots / Settings
├─ Core/
│  ├─ Models/         # SwiftData @Model types
│  ├─ Persistence/    # ModelContainer (local-only)
│  └─ Services/       # Domain services: Holding, Snapshot, Backup
├─ Shared/
│  ├─ L10n/           # Localization helpers
│  └─ Formatters/     # Currency catalog, formatters
├─ Resources/
│  ├─ Localizable.xcstrings   # Single source of truth for user-facing strings
│  └─ Assets.xcassets
└─ Support/
   └─ Cairn.entitlements      # Sandbox + user-selected file access only
```

## Localization

**All user-facing strings live in [`Cairn/Resources/Localizable.xcstrings`](Cairn/Resources/Localizable.xcstrings)**
(Xcode String Catalog). `Text("overview.title")` and friends are auto-localized by SwiftUI.
See PRD §5.5 for the hard rules.

The SwiftLint config includes custom rules that fail the build if `Text(...)`, `.navigationTitle(...)`
or `Button(...)` contain untokenized free-form English.

## Contributing

Pull requests welcome. Before opening one:

1. `make lint && make test` is green.
2. Any new user-facing text has keys in `Localizable.xcstrings` with both `en` and `zh-Hans`
   translations.
3. One logical change per commit, using [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:` …).

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

# Cairn

Family asset management app for Apple platforms. See [PRD.md](PRD.md) for the full product spec.

> The name comes from mountaineering — a cairn is a stack of stones left as a trail marker.
> Each monthly snapshot in the app is one more stone on your financial trail.

## Prerequisites

- Xcode 15.3+ (Swift 5.10+, SwiftData, CloudKit)
- Homebrew packages: `xcodegen`, `swiftlint`
  ```sh
  brew install xcodegen swiftlint
  ```

## Project Generation

The Xcode project is **not** committed — it is regenerated from [`project.yml`](project.yml) via
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make gen          # generate Cairn.xcodeproj
make open         # generate + open in Xcode
make build        # xcodebuild for macOS (change DESTINATION for iOS)
make test         # run unit tests
make lint         # run SwiftLint (incl. i18n custom rules)
make clean        # wipe project + build artifacts
```

## Structure

```
Cairn/
├─ App/          # CairnApp, RootView, tab container
├─ Features/     # Overview / Accounts / Snapshots / Trend / Settings
├─ Core/
│  ├─ Models/         # SwiftData @Model types
│  └─ Persistence/    # ModelContainer + CloudKit wiring
├─ Shared/
│  └─ L10n/           # Localization helpers
├─ Resources/
│  ├─ Localizable.xcstrings   # Single source of truth for user-facing strings
│  └─ Assets.xcassets
└─ Support/
   └─ Cairn.entitlements      # iCloud (CloudKit) + APS
```

## CloudKit Setup

1. Set `DEVELOPMENT_TEAM` in [`project.yml`](project.yml) (or let Xcode pick it up after opening).
2. In Xcode → target **Cairn** → **Signing & Capabilities**, confirm the iCloud capability uses container `iCloud.com.cairn.app` (or change it to one you own and update the entitlement).
3. First run will create the schema in the development environment. Deploy to production via CloudKit Dashboard when ready.

## Localization

**All user-facing strings live in [`Cairn/Resources/Localizable.xcstrings`](Cairn/Resources/Localizable.xcstrings)** (Xcode String Catalog).
`Text("overview.title")` and friends are auto-localized by SwiftUI. See PRD §5.5 for the hard rules.

The SwiftLint config includes custom rules that fail the build if `Text(...)`, `.navigationTitle(...)` or `Button(...)`
contain untokenized free-form English.

## Status

**M1 — Skeleton.** Models, persistence, string catalog, linting are in place. UI beyond tab stubs lands in M2+.

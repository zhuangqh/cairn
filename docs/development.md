# Development Guide

Technical notes for building Cairn from source and contributing. Product spec lives in
[PRD.md](../PRD.md); repository conventions live in [AGENTS.md](../AGENTS.md).

## Prerequisites

- Xcode 26+ on a compatible macOS host, with SDKs for the platforms being built.
  The source uses Liquid Glass APIs from the 26 SDKs with older-OS fallbacks.
  App deployment targets remain macOS 14 and iOS/iPadOS 17; `project.yml` selects
  Swift 5.10 language mode with complete strict concurrency checking.
- Homebrew packages: `xcodegen`, `swiftlint`. The shared Claude Code hook in
  `.claude/settings.json` lints edited Swift files when SwiftLint is installed.
  ```sh
  brew install xcodegen swiftlint
  ```

No Apple Developer account is required for local builds. The shipped entitlements are
sandbox + network client + user-selected files only, and the Makefile signs with an
ad-hoc identity.

## Build & Run

The Xcode project is **not** committed — it is regenerated from [`project.yml`](../project.yml)
via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make gen          # generate Cairn.xcodeproj
make open         # generate + open in Xcode
make build        # xcodebuild for macOS (ad-hoc signed)
make test         # run unit tests
make lint         # run SwiftLint (incl. i18n custom rules)
make clean        # wipe project + build artifacts
```

The default destination is Apple silicon macOS. Override `DESTINATION` when needed:

```sh
make build DESTINATION='generic/platform=iOS Simulator'
```

For a physical iPhone or iPad, run `make open`, select your device and Personal Team
in Xcode's Signing & Capabilities settings, and run the app. Local Xcode signing
selections can be overwritten by project regeneration; keep personal team IDs out
of shared project settings.

## Validation

Follow the scope and authorization rules in [AGENTS.md](../AGENTS.md). Explanation,
diagnosis, and review requests do not authorize fixes; static review alone does
not authorize tests, runtime probes, or a wider audit. The workflow below applies
to authorized implementation work.

Choose checks for the change: review links and content for documentation edits;
run focused tests for domain behavior; build affected platforms for code changes.
Shared UI and platform API changes should also be checked on macOS and iOS when
the SDKs are available. For visual changes, inspect the affected layout and
interaction, including language overrides, accessibility, and resizing as relevant.

To run one existing test class (or `Class/testMethod`) with the Makefile's local
signing settings:

```sh
make test ONLY=CairnTests/SnapshotServiceTests
```

Replace the test class or `DESTINATION` as needed; simulator tests require a concrete
installed simulator destination, not a generic build destination.

Makefile builds filter `xcodebuild` output to errors, warnings, test counts, and
the final status line while preserving its exit status; run with `LOG_FILTER=cat`
for the full log. DerivedData lives in `build/DerivedData` per checkout, so
parallel git worktrees do not share build state.

Use `make test` when the change's impact or a concrete risk warrants the full
macOS suite, or an authorized release workflow requires it. Use `make lint` for Swift changes.
Add regression tests for meaningful behavior, not tests that mirror low-risk
implementation or only assert versions, counts, wording, or field order. Small
demos and version updates should not introduce test frameworks, checkers, or CI
gates. Documentation-only edits do not need an app build or test run.

Domain tests use in-memory SwiftData containers and injected FX stubs. The test
bundle is app-hosted, however, and some tests/previews use `UserDefaults.standard`;
in-memory model fixtures alone do not isolate app startup or settings. Use
disposable data and isolated settings when exercising imports, migrations, or
settings changes. Report checks that could not run and fix failures caused by
the change; after checks pass, repeat or broaden them only for new changes,
failures, or concrete risks. Report unrelated, non-blocking findings without
fixing them. Stop when acceptance criteria are met and summarize changed files,
validation results, and checks not performed.

## UI layout and visual review

Use the existing palette, card and button styles in
[`GlassCardStyle.swift`](../Cairn/Shared/UI/GlassCardStyle.swift). The legacy
`notion…` names now represent Cairn's alpine palette. Match neighboring screens
and reuse shared spacing or sizing values for related components; introduce a
shared layout constant when repeated values need to stay synchronized.

For alignment, choose the intended content edges and columns first. Align mixed
font sizes by text baseline where they belong on one line. Give repeated icons a
consistent slot, and align form labels, input fields, headers, and totals using
shared columns. Independent `Spacer()` layouts in each row can drift with content;
prefer `Grid`, `Table`, or shared column sizing where cross-row alignment matters.
Keep numeric columns trailing-aligned with monospaced digits. Do not insert spaces
or repeatedly nudge individual rows to simulate alignment.

For UI implementation, inspect affected screens in a preview, simulator, or
running app. Use `PreviewSampleData` for model data and isolate settings as
described above. Choose the cases that exercise the change; this is not a full
device/locale matrix for every UI edit:

- **Layout:** compact and expanded widths, relevant iPhone/iPad orientations,
  consistent card edges/insets, text baselines, row columns, and button alignment.
- **Content:** long English/Chinese labels, large or negative amounts, and missing
  values. Important amounts and actions must remain legible without clipping.
- **Appearance and access:** light/dark mode for surface changes, larger text for
  sizing changes, and appropriate contrast, labels, focus, and hit areas.
- **State:** affected empty/populated, loading/error, focused, or keyboard-visible
  states. Optional subtitles and badges should not shift unrelated columns.

For visual refinements, compare before/after at the same viewport and with the
same data; inspect screenshots for alignment and the running UI for interaction.
Fix visible defects caused by the change or blocking its acceptance, then recheck
the affected area. Report other findings without expanding scope. Summarize which
cases were inspected and any unavailable checks.

### Sample-data screenshots

Debug builds accept `-CairnSampleData`, which replaces the persistent store with
`PreviewSampleData` in memory, and `-CairnScreen dashboard|assets|accounts|settings`
to choose the initial screen. The screenshot scripts also pass onboarding, home
currency (USD), language, and appearance settings as launch arguments, which are
read for that launch only, so the user's store and saved settings are not used.

```sh
make screenshot-ios SCREEN=assets LANG_CODE=zh-Hans APPEARANCE=dark
```

This builds for the iOS Simulator, installs over the booted simulator's Cairn
(set `DEVICE=<udid>` for another), and writes
`build/screenshots/ios-<screen>-<lang>-<appearance>.png`. Its data container is
left untouched. `make screenshot` is the macOS equivalent and writes
`build/screenshots/<screen>-<lang>-<appearance>.png`. It needs Screen Recording
permission for the terminal, launches a separate instance from `build/`, and exits
if one from that build is already running. Instances from Xcode or `/Applications`
are left alone. The scripts cover launch state only; use the running app for
interaction, resizing, and larger text.

## Release Builds

Publishing or pushing a release requires user confirmation under
[AGENTS.md](../AGENTS.md); preparing a local build does not authorize those actions.

Pushing a tag named `v*` (for example `v0.1.0`) runs the GitHub release workflow:

1. Install `xcodegen` and `swiftlint` on a macOS runner.
2. Run SwiftLint and the macOS test suite with ad-hoc signing.
3. Build `build/Cairn-x.y.z.dmg` with the shipped sandbox, network-client, and file-access entitlements.
4. Publish the DMG to a GitHub Release with generated release notes.

Manual `workflow_dispatch` runs build the same DMG and expose it as a workflow artifact.

## Project Structure

```
Cairn/
├─ App/          # CairnApp, RootView, tab container
├─ Features/     # Dashboard / Overview / Accounts / Snapshots / Assets / Settings
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
   └─ Cairn.entitlements      # Sandbox + network client + user-selected file access
```

## Localization

**All user-facing strings live in [`Cairn/Resources/Localizable.xcstrings`](../Cairn/Resources/Localizable.xcstrings)**
(Xcode String Catalog). `Text("overview.title")` and friends are auto-localized by SwiftUI.
See PRD §5.5 for the hard rules.

The SwiftLint config includes custom rules that fail the build if `Text(...)`, `.navigationTitle(...)`
or `Button(...)` contain untokenized free-form English.

## Contributing

Pull requests welcome. Before opening one:

1. Run the checks appropriate to the change above and describe the results or
   limitations in the PR. Release CI requires the full macOS suite and lint.
2. Any new user-facing text has keys in `Localizable.xcstrings` with both `en` and `zh-Hans`
   translations.
3. Keep one logical change per commit and follow the commit standards below.

### Commit preparation and messages

For an authorized commit task, inspect the working tree and index, stage only the
intended files or hunks, then check the staged result:

```sh
git status --short
git diff --cached --stat
git diff --cached --check
```

Read each patch once, not before and again after staging. An agent that made
the changes in the current session already knows them and confirms the scope
from the stat; read the patch (`git diff --cached -U1 -- <path>`) for work it did
not author or for any file whose stat is unexpected. Show only changed lines for
bulky files such as string catalogs. If the index changes after review, inspect
the updated staged content. Preserve unrelated work and existing
staging; ask the user to resolve unrelated staged changes rather than silently
including or unstaging them. Do not create an empty commit to complete a task.

Use the [Conventional Commits 1.0.0 format](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>[optional scope][!]: <summary>

[optional body explaining why and any relevant validation]

[optional footers]
```

Choose the type from the actual change: `feat` adds behavior, `fix` corrects a bug,
`docs` changes documentation, and `refactor` changes structure without changing
behavior. Use `test`, `perf`, `build`, `ci`, or `chore` where they fit. The optional
scope identifies an area such as `snapshots`, `ui`, or `agents`. Write a concise
imperative summary describing the result, not a vague message such as "update
files". For example:

```text
docs(agents): define staged diff review and commit standards
```

For simple changes, a subject alone is sufficient. Use a body for motivation,
non-obvious consequences, and useful validation details; do not claim checks that
were not run. Use `!` or a `BREAKING CHANGE:` footer only for an actual incompatible
change, and describe its impact and migration path.

Prepare the proposed scope and message before requesting commit confirmation.
Committing does not authorize a push, amend, or other history rewrite. After an
authorized commit, report its ID, what it contains, validation results, and any
remaining staged or unstaged work. These instructions do not require commit hooks,
message linters, or new CI gates.

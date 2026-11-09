# Cairn development

Cairn is a local-first family net-worth app. macOS is the primary distribution
target; iPhone and iPad share the SwiftUI codebase.

## Task scope and authorization

- Identify the goal, permitted files or objects, constraints, and acceptance
  criteria from the current request. If a path is unclear, start with one bounded
  search in the likely location.
- Explanation, diagnosis, and review requests authorize investigation and
  reporting, not edits. A static review does not authorize tests, runtime probes,
  or a broader audit. The implementation guidance below applies only to tasks
  that authorize changes.
- Make the smallest sufficient change using existing code and patterns. Do not
  introduce compatibility layers, feature flags, dependencies, or abstractions.
  If the task requires one, explain the need as a scope extension before adding it.
- Proceed with reads, edits, and checks within the authorized scope. Before
  committing, pushing, deploying, writing to external systems, or materially
  expanding scope, finish the authorized preparation, explain the reason and
  minimum additional action, and obtain the user's confirmation.

## Build and project structure

- Use Xcode 26+ with the needed platform SDKs, XcodeGen, and SwiftLint. Deployment
  targets remain macOS 14 and iOS/iPadOS 17. `project.yml` sets Swift 5.10 language
  mode and complete strict concurrency checking.
- Edit `project.yml` for project settings; `Cairn.xcodeproj` is generated and
  ignored. Regenerate it with `make gen`.
- Put screens in `Cairn/Features`, domain logic in `Cairn/Core/Services`, SwiftData
  models and container setup in `Cairn/Core`, and reusable UI/localization in
  `Cairn/Shared`. Reuse existing services and components.

| Task | Command |
| --- | --- |
| Generate project | `make gen` |
| Build macOS | `make build` |
| Build iOS Simulator | `make build DESTINATION='generic/platform=iOS Simulator'` |
| Full macOS unit suite | `make test` |
| SwiftLint, including localization rules | `make lint` |

The Makefile defaults to Apple silicon macOS and ad-hoc signing with the shipped
entitlements. Override `DESTINATION` for another installed destination. See
`docs/development.md` for focused test commands and device signing.

## Swift and platform UI

- Existing persistence services use `@MainActor`. Keep SwiftData contexts and
  live models on their owning actor; pass IDs or Sendable values across actors.
  Resolve isolation issues rather than suppressing concurrency diagnostics.
- Use async networking and respect view-task cancellation. Keep expensive work
  out of SwiftUI `body`; reuse the FX cache and snapshot index for aggregations.
- Guard platform-specific APIs with conditional compilation and newer APIs with
  availability checks. Preserve older-OS fallbacks, including Liquid Glass.
- Preserve macOS sidebar and iOS tab navigation, adaptive layouts, and unsaved
  edits across resizing/rotation. Support keyboard dismissal, VoiceOver,
  scalable text, and Reduce Motion in affected UI; reuse shared styles.
- Add user-facing copy to `Cairn/Resources/Localizable.xcstrings` in both `en` and
  `zh-Hans`, including errors and accessibility labels. Honor `LocalizationService`
  overrides, including its bundle for navigation chrome. Use locale-aware
  formatting and decimal parsing; user-authored names and notes stay literal.

## UI layout and visual alignment

- Give page headings, cards, rows, and toolbars deliberate shared alignment
  guides. Keep sibling padding, spacing, control heights, and icon slots
  consistent; reuse the styles in `Cairn/Shared/UI/GlassCardStyle.swift`.
- Use shared grid/table columns and text baselines for related labels and values.
  Fix alignment in layout structure rather than with per-row offsets, padding
  patches, or space characters. Small optical adjustments belong inside shared
  icon components, not in each screen.
- Align comparable amounts to the trailing edge with monospaced digits and
  consistent display precision. Keep labels leading-aligned; never alter stored
  precision or hide significant digits just to fit a column.
- Let layouts adapt to long names, translated copy, and larger text. Reflow or
  wrap before shrinking text; keep controls reachable and preserve clear
  hierarchy. Reserve Liquid Glass for floating navigation/controls; data surfaces
  should remain quiet and readable.
- For UI implementation, inspect the rendered result and fix misalignment,
  clipping, overlap, and uneven spacing caused by the change or blocking its
  acceptance. Select representative cases using `docs/development.md`; report
  unavailable rendering rather than treating compilation as visual validation.

## Data integrity and privacy

- Use `Decimal` for monetary values and financial calculations. Accounts can hold
  multiple currencies, with at most one active holding per currency per account.
- Per-holding `Snapshot.periodMonth` is a **day** key normalized with
  `Snapshot.normalizeDay`; its legacy name preserves store compatibility.
  `PortfolioSnapshot` remains monthly, keyed by month and home currency using
  `Snapshot.normalize`. Preserve its captured entries, totals, and FX rates when
  live holdings or rates change. Both key types use UTC.
- Preserve atomic batch saves and rollback on restore failure. Distinguish blank
  input from zero. Model changes must account for existing stores, relationships,
  `PersistenceController.schema`, and backward-compatible `.cairn` backups.
  Never fix a migration or test failure by deleting the user's store.
- Keep storage local with CloudKit disabled. Network traffic is limited to public
  FX requests; do not send holdings, balances, names, or backups, or add analytics.
  Preserve sandbox and user-selected-file entitlements; keep personal data out
  of logs, fixtures, and commits.
- Installation, data replacement, signing/entitlement changes, and publishing
  belong only to tasks that call for them. `make install`/`reinstall` stops and
  replaces the installed app; it is not a routine verification step.

## Testing and verification

- For authorized changes, choose relevant checks: link/content checks for docs,
  focused XCTest tests for behavior, affected builds for code, and rendered
  inspection for UI. Check both platforms for shared UI/API changes when SDKs
  are available. These are not extra requirements for read-only requests.
- For reversible, low-risk changes, do not add tests that restate implementation.
  Add regression coverage when it protects meaningful behavior; do not write
  tests solely for version numbers, file counts, wording, or field order.
  Do not add test frameworks, checkers, or CI gates for small demos or version
  updates.
- Use in-memory SwiftData fixtures and injected `FXRateFetching` stubs for domain
  tests. Cover relevant money/date boundaries, compatibility, and failure paths.
  Use disposable data for import/migration checks; isolate settings as well as
  model data.
- Run checks relevant to the change. After they pass, repeat or broaden validation
  only for new changes, failures, or concrete risks. Use the full suite when the
  impact warrants it or the authorized release workflow requires it; release CI
  requires tests and lint.
- Follow `.swiftlint.yml`; avoid unrelated reformatting.

## Commit standards

- When preparing a commit, inspect `git status --short`, then read the complete
  `git diff --cached` (equivalently `git diff --staged`). A file list, diff summary,
  working-tree diff, or conversation history does not replace reviewing the
  actual staged patch. Recheck it if the staged content changes.
- Stage only intended files or hunks within the approved scope. Preserve other
  staged and unstaged work; unrelated staged changes must be resolved with the
  user before committing. Keep one logical change per commit.
- Derive the message from the final staged diff. Use Conventional Commits:
  `<type>[optional scope][!]: <summary>`, with a concise imperative summary.
  Use `feat` for features, `fix` for bug fixes, and `docs`, `refactor`, `test`,
  `perf`, `build`, `ci`, or `chore` as appropriate; scope names the affected area.
- Add a body when needed to explain the reason, non-obvious effects, and relevant
  validation actually performed. Mark real breaking changes with `!` or a
  `BREAKING CHANGE:` footer and explain the impact and migration path.
- Present the proposed scope and message for the confirmation required above.
  Commit authorization does not authorize pushing or rewriting existing commits.
  After committing, report the commit ID and any remaining changes.

## Completion and delivery

- Complete the authorized work, relevant verification, and fixes for failures it
  causes. Report blockers and continue independent work within scope. Discovering
  an issue does not authorize fixing it; list unrelated, non-blocking findings
  at delivery rather than expanding the task.
- When archiving task documentation, retain only the needed documents, scripts,
  and result summaries. Do not remove unrelated or user-owned artifacts.
- Stop when acceptance criteria are met. Report changed files, validation results,
  checks not performed, and any remaining limitations.

## References by task

- `docs/development.md`: setup, visual review, tests, commits, signing, and releases.
- `PRD.md`: product requirements; older sections predate daily holding snapshots.
  Reconcile discrepancies with the task and current code/tests.
- `docs/achievement-system-design.md`: achievement rules and presentation.

Read only references relevant to the task. Keep detailed release/migration
procedures in task-specific docs or skills rather than expanding this file.

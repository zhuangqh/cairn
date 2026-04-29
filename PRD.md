# Cairn — Family Asset Management App PRD

> Version: v0.2 (Draft)
> Author: (you)
> Target platforms: **macOS primary**; iOS / iPadOS sources stay buildable but are not supported for distribution
> Distribution: open-source (Apache-2.0). No Apple Developer account is assumed — macOS releases are ad-hoc signed DMGs built by GitHub Actions, and the shipped entitlements are sandbox + network client + user-selected files only. There is no App Store release pipeline.
> Last updated: 2026-04-18
> Working language: English. All code identifiers, comments, commit messages, and documentation are in English. All user-facing strings MUST go through `String(localized:)` / String Catalogs from day one (see §5.5).
> Name origin: a *cairn* is a stack of stones left as a trail marker by hikers; each monthly snapshot in the app is one more stone on your family's financial trail.

---

## 1. Overview

### 1.1 Background & Motivation
A family's assets are typically spread across multiple currencies, multiple accounts, and multiple categories (cash, equities, real estate, electronics, etc.). Existing ledger apps focus on transaction flow; investment apps focus on per-ticker tracking. Neither gives a "whole-family snapshot + long-term trend" view.

Cairn is designed for a **single primary bookkeeper** (the family CFO) who organizes data by family `Member` on their own device, records monthly snapshots, and visualizes net-worth trends.

### 1.2 Positioning
One-liner: **A monthly net-worth check-up app for families.**

- Not a transaction ledger
- Not a per-ticker real-time quote app
- Focused on "what we own now + what it's worth + how it evolved"

### 1.3 Target Users
- Families holding multi-currency assets (e.g. CNY / USD / HKD simultaneously)
- Users who want to review net worth on a monthly cadence
- Users willing to enter data manually in exchange for privacy and simplicity

### 1.4 Design Principles
1. **Privacy first** — data stays on-device; no cloud sync, no third-party analytics, no account-aggregation integrations.
2. **Low entry cost** — monthly update completes in a few minutes; primary path ≤ 3 taps.
3. **Apple-native** — SwiftUI + SwiftData; leverage system components (Charts, Widgets, Siri).
4. **Mac-first, sources portable** — one codebase primarily targets macOS; iPad/iPhone targets still compile but are unsupported.
5. **Localization-ready from day one** — no hardcoded user-facing strings; ship `en` and `zh-Hans` at launch.
6. **Open-source friendly** — no capabilities that require a paid Apple Developer account. Users move data between Macs via a JSON backup file.

---

## 2. Scope & Roadmap

### 2.1 v1 (MVP) — Investment Tracking + Trend
- Family member profiles
- Cash & equity positions (total value, not per-ticker)
- Multi-currency support + live FX rates
- Monthly snapshots + net-worth chart
- Local storage + manual JSON backup export/import (drop the file in iCloud Drive / Dropbox for cross-Mac transfer)

### 2.2 v1.1 — Physical Assets
- Real estate (houses, cars, etc.)
- Personal electronics (phones, laptops, etc.)
- Asset metadata (acquisition date, sale date, price, name)

### 2.3 v2+ (placeholder, not designed yet)
- Automatic depreciation rules
- Stock quote API integration
- Asset icon library / custom icons
- Widgets & Apple Watch
- Siri Shortcuts ("Update this month's assets")
- Export to PDF / CSV

---

## 3. Core Concepts & Data Model

### 3.1 Entities

| Entity | Description |
|---|---|
| `Member` | Family member profile (name, avatar, note) |
| `Account` | A container under a Member (cash / equity / real estate / device). **Not bound to a currency.** |
| `Holding` | A **single-currency position** inside an Account (e.g. "CMB-CNY", "CMB-AUD", "Futu-USD"). Smallest unit for entry and snapshots. |
| `Snapshot` | Valuation record of a `Holding` for a given month (amount in the holding's native currency) |
| `Asset` (v1.1) | Physical asset (house, car, device) with acquisition/sale/valuation metadata |
| `FXRate` | FX rate cache (base → quote, by day) |
| `Settings` | User settings (home currency / theme / language override / backup) |

> **Key design**: An Account can contain multiple Holdings of different currencies. Example: Member = "Me" / Account = "Primary Cash" may contain Holdings in CNY, AUD, USD at once; Member = "Me" / Account = "Futu" may contain Holdings in USD and HKD.

### 3.2 SwiftData Model Sketch (pseudo-code)

```swift
@Model final class Member {
    var id: UUID
    var name: String
    var avatarData: Data?
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var accounts: [Account]
}

@Model final class Account {
    var id: UUID
    var name: String                 // e.g. "CMB Checking"
    var kind: AccountKind            // .cash / .stock / .realEstate / .device
    var note: String?
    var isArchived: Bool
    @Relationship var member: Member?
    @Relationship(deleteRule: .cascade) var holdings: [Holding]
}

enum AccountKind: String, Codable { case cash, stock, realEstate, device }

@Model final class Holding {
    var id: UUID
    var currency: String             // ISO 4217, e.g. "CNY" / "AUD" / "USD"
    var label: String?               // Optional note, e.g. "Emergency fund"
    var isArchived: Bool
    @Relationship var account: Account?
    @Relationship(deleteRule: .cascade) var snapshots: [Snapshot]
}

@Model final class Snapshot {
    var id: UUID
    var periodMonth: Date            // normalized to the 1st of the month 00:00 UTC
    var amount: Decimal              // amount in holding's native currency
    var recordedAt: Date
    @Relationship var holding: Holding?
}

@Model final class FXRate {
    var base: String                 // e.g. "USD"
    var quote: String                // e.g. "CNY"
    var rate: Decimal
    var date: Date
}
```

### 3.3 Invariants
- A `Holding` has at most one `Snapshot` per `periodMonth` (upsert semantics).
- `Holding.currency` is immutable once created. To change currency, archive the Holding and create a new one.
- Within a single `Account`, no two Holdings may share the same `currency` (enforced in UI + validated on save).
- All monetary values use `Decimal`; UI converts to the home currency on the fly.
- `periodMonth` is stored in UTC to avoid timezone drift across devices.

### 3.4 Localization-Related Data Rules
- **No user-facing string is stored in the database.** Enums like `AccountKind` are persisted as stable tokens (`"cash"`, `"stock"`, …) and rendered via localized lookup.
- Currency codes stored as ISO 4217; display formatting derives from the user's locale.
- Dates stored as absolute `Date`; formatted via `Date.FormatStyle` with the current locale.
- Member names and account names are user-authored free text (not localized).

---

## 4. Functional Requirements

### 4.1 Member Management

#### F-MEM-1 Create / Edit / Delete Member
- Fields: name (required), avatar (optional, PhotosPicker), note.
- Deletion requires confirmation and cascades to all accounts and snapshots.
- First launch guides the user to create the first Member.

#### F-MEM-2 Member Switching
- Top-level selector between "All family" view and "Single member" view.
- "All family" aggregates across all Members.

---

### 4.2 Accounts & Holdings

#### F-ACC-1 Create Account
- Must belong to a Member.
- Kind: cash / equity (v1); real estate / device (v1.1).
- Name, note. **Not bound to a currency.**
- Multiple accounts of the same kind are allowed per Member (e.g. "CMB Checking", "HSBC Premier").

#### F-ACC-2 Add Holdings to an Account
- Any number of Holdings per Account, each pinned to a single currency.
- Fields: currency (ISO 4217 dropdown with frequently used currencies pinned to top), optional label.
- Constraint: currency unique within an Account.
- Example: Account "Primary Cash" → Holdings [CNY, AUD, USD].

#### F-ACC-3 Account List & Detail
- List grouped by kind.
- Each Account row shows the sum of its Holdings' latest snapshots (converted to home currency); expand to see per-currency breakdown.
- Account detail: list of Holdings + a small account-level trend chart.

#### F-ACC-4 Edit / Archive
- Account: rename, edit note, archive.
- Holding: currency is immutable; can be archived or deleted (delete cascades snapshots; confirmation required).
- Archived items are excluded from aggregations but preserved in history.

---

### 4.3 Snapshot Entry

#### F-SNAP-1 Monthly Batch Entry (primary path, Excel-style — see §4.3.5)
- Prominent CTA on Overview: "Update this month".
- Opens the **spreadsheet-style batch entry screen**; updates every Holding for the month in one go.
- Default `periodMonth` = current month; can switch to any past month for backfill.
- Entry granularity: one row per Holding.

#### F-SNAP-2 Single-Entry Quick Add
- From Holding detail → "+ New Snapshot".
- Fields: month (default current), amount.

#### F-SNAP-3 Edit / Delete Snapshot
- Amount is editable; `periodMonth` is not (delete and recreate).

#### F-SNAP-4 Reminder
- Optional local notification on the 1st of each month: "Time to update your assets".

#### F-SNAP-5 Spreadsheet-Style Batch Entry (core UX, mandatory)

**Design goal**: feel like editing an Excel sheet — fewest taps, fewest screen changes.

**Layout (iPad / Mac first; iPhone adapts — see §4.3.6)**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Month: [2026-04 ▼]   Home: CNY   [Fill from last] [Clear] [Save all]        │
├──────────────┬──────────────┬──────┬──────────────┬──────────────┬─────────┤
│ Member       │ Account      │ Ccy  │ Last month   │ This month   │ ≈ CNY   │
├──────────────┼──────────────┼──────┼──────────────┼──────────────┼─────────┤
│ Dad          │ Primary Cash │ CNY  │    120,000   │ [ 125,300  ] │ 125,300 │
│              │              │ AUD  │     8,500    │ [   8,500  ] │  40,120 │
│              │              │ USD  │     3,000    │ [   3,200  ] │  23,400 │
│              │ Futu         │ USD  │    52,000    │ [  54,100  ] │ 395,800 │
│              │              │ HKD  │    18,000    │ [  17,500  ] │  16,050 │
│ Mom          │ CMB Checking │ CNY  │    60,000    │ [  62,000  ] │  62,000 │
├──────────────┴──────────────┴──────┴──────────────┴──────────────┼─────────┤
│                                                          Total   │ 662,670 │
└──────────────────────────────────────────────────────────────────┴─────────┘
```

**Interaction details**
- One row per Holding; only the "This month" column is editable.
- If no snapshot exists yet for the month: the input shows last month's value as a greyed placeholder; tapping clears it for input.
- If a snapshot exists: the existing value is shown in primary text color.
- Standard platform text-field focus behavior is supported. Custom spreadsheet keyboard navigation (`Tab`, arrows, `Enter`) is not part of the current implementation.
- Inputs update the "≈ home" column and the footer total in real time.
- Edited-but-unsaved rows show a yellow dot on the left; saved rows show a green dot.
- Top-bar actions:
  - `Fill from last` — populate all empty cells with last month's amount.
  - `Clear` — clear all this-month inputs (confirmation required).
  - `Save all` — commit all changes as an atomic upsert (roll back on failure).
- Leaving the screen with unsaved edits prompts Save / Discard.
- Grouping: sticky section header per Member; sections are collapsible.
- Empty cell handling: if a Holding is left blank, **no snapshot is written**; the trend treats the month as missing (no carry-forward).

**Performance**
- `LazyVStack` rendering; comfortable with large household holding lists.
- Amounts bound as `Decimal`; formatting and parsing use the current locale (decimal separator, grouping).

#### F-SNAP-6 iPhone Adaptation (portrait & landscape)

- **Portrait (compact)**: condensed list. "Last month" column is hidden and shown as secondary inline text beneath the input. Columns shown: Member (section header) · Account + Ccy · This month · ≈ home.
- **Landscape**: switch to the full 6-column grid (same as iPad / Mac).
- Orientation changes preserve in-flight unsaved edits (values, focused cell, scroll position).
- The screen declares `supportedInterfaceOrientations` to allow landscape even if the rest of the app is portrait-only.

---

### 4.4 Multi-Currency & FX

#### F-FX-1 Home Currency
- First-launch onboarding picks the home currency (default from `Locale.current.currency`).
- All aggregated figures render in the home currency.

#### F-FX-2 Live Rate Fetching
- Source: Frankfurter API (`https://api.frankfurter.app`), ECB data, free, no API key.
- Fallback: exchangerate.host.
- Fetch strategy:
  - On app launch, refresh if last fetch > 6h ago.
  - Pull-to-refresh forces a refetch.
  - Use the last cached value when offline.
- Storage: `FXRate` cached by date.

#### F-FX-3 Historical Rates
- For trend aggregation, the default is the rate **as of the snapshot's month-end**.
- v1 simplification: use latest rates for all historical conversions.
- v1.1 enhancement: store per-month rate snapshots and use the month-aligned rate for historical charts.

---

### 4.5 Trend Visualization

#### F-CHART-1 Net-Worth Curve
- Overview default chart: total family net worth (home currency) over the last 12 months.
- Range toggles: 6M / 12M / ALL.
- Tech: Swift Charts.

#### F-CHART-2 Dimensional Breakdown
- Stacked by kind (cash / equity / …).
- Stacked by Member.
- Stacked by currency.

#### F-CHART-3 Data-Point Interaction
- Long-press a point to reveal a month breakdown: amount + MoM change + composition.

---

### 4.6 Settings

- Home currency.
- Monthly reminder toggle + time.
- Language override (follow system / `en` / `zh-Hans`).
- Backup: **Export** current store to a `.cairn` JSON file; **Import** replaces the entire store with a backup file (destructive, confirmed).
- Data export: CSV (v1.1).
- About, privacy policy.

---

### 4.7 v1.1 Physical Assets

```swift
@Model final class Asset {
    var id: UUID
    var name: String
    var category: AssetCategory      // .realEstate / .vehicle / .electronics / .other
    var purchaseDate: Date
    var purchasePrice: Decimal
    var purchaseCurrency: String
    var saleDate: Date?
    var salePrice: Decimal?
    var currentValue: Decimal?       // manual valuation
    var currentValueUpdatedAt: Date?
    var iconName: String?            // reserved
    var note: String?
    @Relationship var member: Member?
}
```

- For "whole-family net worth", a physical asset is counted at `currentValue` (fallback to `purchasePrice` if nil).
- Sold assets (`saleDate != nil`) are excluded from current net worth but retained in history.

---

## 5. Non-Functional Requirements

### 5.1 Performance
- Cold start → Overview visible ≤ 1.5s (excluding network FX fetch).
- At 10 years × 12 months × 50 accounts ≈ 6000 snapshots, chart rendering < 300ms.

### 5.2 Privacy & Security
- Data stays on-device in the sandboxed Application Support directory. No cloud sync.
- The only network egress is FX rate fetches; those carry no user data.
- Backup files are plain JSON and remain wherever the user puts them (local disk / iCloud Drive / Dropbox / Git).
- No third-party analytics SDK; no ad SDK.
- App-level Face ID / Touch ID lock (v1.1).

### 5.3 Accessibility
- Dynamic Type and VoiceOver support.
- Native dark mode.

### 5.4 Compatibility
- Minimum: iOS 17 / iPadOS 17 / macOS 14 (SwiftData requirement).
- Fully usable offline (except FX refresh).

### 5.5 Internationalization & Localization (i18n / l10n)

**Launch locales**: `en` (base), `zh-Hans`.

**Hard rules — enforced from commit #1:**
1. **Zero hardcoded user-facing strings.** Every `Text`, `navigationTitle`, alert, button label, accessibility label, and error message uses `String(localized:)` or a `LocalizedStringResource`. Exception: user-authored content (member/account names, notes).
2. **Xcode String Catalog (`Localizable.xcstrings`)** is the single source of truth. No scattered `Localizable.strings` files.
3. **Lint**: a CI check (SwiftLint custom rule or a simple grep pass) rejects `Text("...")` or `.navigationTitle("...")` containing untokenized literals. Intentional exceptions are annotated `// swiftlint:disable:next ...`.
4. **Numbers & currencies**: use `Decimal.formatted(.currency(code:))` and `Decimal.formatted(.number)` — never manually concatenate `"$" + amount`.
5. **Dates**: use `Date.FormatStyle` / `.formatted(date:time:)` — never build strings from date components manually.
6. **Pluralization**: use the String Catalog's plural variants (backed by `%lld`) for every count-bearing string (e.g. "3 accounts").
7. **RTL readiness**: use `leading`/`trailing` (not `left`/`right`); mirror SF Symbols where relevant; spot-check layouts with `-NSForceRightToLeftWritingDirection YES` even though Arabic/Hebrew are not shipping at launch.
8. **Locale-aware input parsing**: the batch entry screen parses decimals using the current locale (comma vs. dot, grouping separator).
9. **Language override**: Settings lets the user run the app in a different language than the system. Implemented by swapping the localization bundle at runtime.
10. **Testing**: one UI snapshot test each in `en`, `zh-Hans`, and the pseudolocale to catch truncation and missing keys.

**String naming convention** (inside the catalog):
```
overview.title                   = "Overview"
overview.cta.updateThisMonth     = "Update this month"
entry.header.lastMonth           = "Last month"
entry.header.thisMonth           = "This month"
entry.total                      = "Total"
entry.action.fillFromLast        = "Fill from last"
entry.action.clear               = "Clear"
entry.action.saveAll             = "Save all"
account.kind.cash                = "Cash"
account.kind.stock               = "Equity"
account.kind.realEstate          = "Real estate"
account.kind.device              = "Device"
snapshot.delete.confirm.title    = "Delete snapshot?"
error.fx.fetchFailed             = "Couldn't fetch FX rates. Using cached values."
```

Keys are namespaced by feature, lowerCamelCase segments separated by dots.

---

## 6. Technical Architecture

### 6.1 Stack
| Layer | Choice |
|---|---|
| UI | SwiftUI (multi-platform; macOS primary) |
| Persistence | SwiftData (local-only store; `cloudKitDatabase: .none`) |
| Cross-device transfer | JSON backup file (`BackupService`) |
| Charts | Swift Charts |
| Networking | URLSession + async/await |
| Architecture | SwiftUI-native MV + `@Observable` view models |
| Localization | Xcode String Catalog (`.xcstrings`) |

### 6.2 Module Layout
```
Cairn/
├─ App/                 # CairnApp, RootView, tabs
├─ Features/
│  ├─ Members/
│  ├─ Accounts/
│  ├─ Snapshots/
│  ├─ Trend/
│  ├─ Assets/           # v1.1
│  └─ Settings/
├─ Core/
│  ├─ Models/           # SwiftData @Model
│  ├─ FX/               # FXService, FXRateStore
│  ├─ Aggregation/      # NetWorthCalculator
│  ├─ Persistence/      # ModelContainer (local-only)
│  └─ Services/         # HoldingService, SnapshotService, BackupService
├─ Shared/
│  ├─ Formatters/       # CurrencyFormatter, DateFormatter wrappers
│  ├─ L10n/             # LocalizationService, LocalizedStringResource helpers
│  ├─ Theme/
│  └─ Components/
└─ Resources/
   ├─ Localizable.xcstrings
   └─ Assets.xcassets
```

### 6.3 Key Services
- `FXService` — fetches & caches FX rates; exposes `convert(amount:from:to:on:)`.
- `NetWorthCalculator` — given (members, time range, grouping dimension) returns trend data.
- `SnapshotUpserter` — diff-based upsert for the batch entry screen.
- `LocalizationService` — resolves the language override and feeds the in-app `Bundle` for localized lookups.

---

## 7. Information Architecture & Key Screens

### 7.1 Tabs
1. **Overview** — total net worth + trend chart + "Update this month" CTA.
2. **Accounts** — grouped by Member / kind.
3. **Assets** *(v1.1)* — physical assets.
4. **Settings**.

### 7.2 Screens
| # | Screen | Key components |
|---|---|---|
| S1 | Onboarding | Pick home currency, language preference, create first Member |
| S2 | Overview | Swift Charts curve, Member selector, "Update this month" CTA |
| S3 | Members | List + edit |
| S4 | Account list | Grouping + create |
| S5 | Account detail | Holding list + per-Holding trend |
| S6 | **Spreadsheet batch entry** | Excel-style grid, keyboard nav, live totals (§4.3.5 / §4.3.6) |
| S7 | Settings | Home currency, reminder, language override, backup export/import |

### 7.3 Primary Journey — Monthly Update
1. Notification on the 1st → open app.
2. Overview → "Update this month" → batch entry screen.
3. Inputs pre-filled with last month's values → edit only the ones that changed.
4. `Save all` → return to Overview; the curve extends by one point.
5. Total time < 3 minutes.

---

## 8. Success Metrics (post-launch, observational)
- MAU / installs (no remote analytics; voluntary feedback only).
- Average time for a monthly update < 3 minutes.
- ≥ 60% of users retain at least 3 consecutive months of snapshots.

---

## 9. Risks & Decisions

### 9.1 Risks
| Risk | Mitigation |
|---|---|
| Free FX API downtime | Dual-source fallback (Frankfurter → exchangerate.host); allow manual rate override. |
| Lossy restore from an older backup | `BackupPayload.version` is stamped and checked on import; forward-compat migrations live in `BackupService`. |
| Missed monthly entry → curve gaps | Backfill supported; chart marks missing months explicitly rather than silently interpolating. |
| SwiftData early-stage bugs | Retry critical writes; keep a local audit log. |
| Missing localization keys shipping to prod | String Catalog `stale` warnings treated as CI errors; pseudolocale UI test. |

### 9.2 Confirmed Decisions
1. ✅ **Multi-currency per account** via Account → multiple Holdings, not via multiple accounts.
2. ✅ **No joint accounts** — assets always belong to a single Member.
3. ✅ **Monthly snapshot granularity only.**
4. ✅ **No import tooling in v1.**
5. ✅ **Equity Holding records a single total per currency** — no separate "cash-in-brokerage" vs "market value" split.
6. ✅ **iPhone batch entry supports landscape**: portrait = compact list (hides "Last month" column); landscape = full 6-column grid. Unsaved edits are preserved across rotation.
7. ✅ **Working language is English**; the app ships `en` + `zh-Hans` at v1.

### 9.3 Open Questions
None at this time.

---

## 10. Milestones (ordered; no time estimates)

- **M1 Skeleton** — multi-platform Xcode project (macOS primary), SwiftData models with a local-only store, String Catalog wired in, localization lint in CI, JSON backup export/import.
- **M2 Core CRUD** — Member / Account / Holding / Snapshot.
- **M3 FX & Aggregation** — `FXService`, `NetWorthCalculator`.
- **M4 Visualization** — Swift Charts trend + dimensional stacking.
- **M5 Spreadsheet Entry** — Excel-style grid, keyboard nav, live totals, atomic batch upsert, onboarding, monthly reminder, iPhone landscape.
- **M6 v1 Polish** — localization pass (`en` + `zh-Hans` + pseudolocale), accessibility, empty states, error handling.
- **M7 v1.1 Physical Assets** — `Asset` model and screens.
- **M8 v2 Planning** — depreciation, quote API, widgets, Siri.

---

## Appendix A — Glossary
- **Snapshot** — valuation of a Holding for a given month (monthly granularity).
- **Holding** — single-currency position within an Account; smallest unit of entry and trend.
- **Home currency** — the currency the user chose for aggregated display.
- **Member** — family member profile; the data isolation unit.
- **Net worth** — sum of all Holdings' latest valuations converted to the home currency (v1 has no liabilities).

## Appendix B — Future Entities
- `Liability` (mortgages, credit cards) → real "net worth".
- `Goal` (down payment, retirement).
- `Tag` (e.g. "emergency fund", "education fund").

<h1 align="center">
  <img src="docs/assets/icon.png" alt="Cairn" width="160" height="160"><br>
  Cairn
</h1>

<p align="center">
  <b>A monthly net-worth check-up app for families — on your Mac, iPhone, and iPad.</b><br>
  Private by design · Multi-currency · Apple-native
</p>

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Apache%202.0-blue.svg"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20iOS%2FiPadOS%2017%2B-lightgrey">
  <img alt="Built with" src="https://img.shields.io/badge/SwiftUI%20%2B%20SwiftData-orange">
</p>

---

> The name comes from mountaineering — a **cairn** is a stack of stones left as a trail marker.
> Each monthly snapshot in the app is one more stone on your family's financial trail.

Cairn gives the family CFO a single, calm place to answer one question every month:
**"What do we own, what is it worth, and how is it trending?"** No transactions to
categorize, no API keys to configure, no cloud account to sign into.

## ✨ Features

### 👨‍👩‍👧 Whole-family view, organized by member
Create a profile for each family member — group their
accounts under them, and switch between a per-member view and an aggregated
"All family" view with a single tap.

### 💱 Multi-currency without the spreadsheet gymnastics
One account can hold positions in **CNY, USD, HKD, AUD, …** at the same time. Cairn
fetches live FX rates from the ECB (Frankfurter API, no API key) and converts everything
to your chosen home currency on the fly. Works offline with cached rates.

### 📅 Excel-style monthly batch entry
The core workflow. One screen, one row per holding, last month's values pre-filled —
edit only what changed, `Save all`, done. Designed to take **under 3 minutes a month**.

- Keyboard navigation (`Tab`, `↑`/`↓`, `Enter`)
- Live running total in your home currency
- Atomic save — all rows commit together or none do
- Backfill any past month

### 📈 Net-worth trend, at a glance
A Swift Charts curve of total family net worth over **6M / 12M / All time**, with
breakdowns by **account kind**, **member**, or **currency**, and an overlay of your
cumulative physical-asset value on the same chart. Hover or long-press any point for
that month's composition and MoM change.

### 🏦 Accounts & holdings that match reality
Cash, brokerage, and similar financial accounts. An account is *not* pinned to a
single currency — add as many single-currency **holdings** underneath as you need.

### 🏠 Physical assets alongside the financial ones
Track real estate, vehicles, devices, and other tangible assets in their own tab,
with a cumulative value chart that lines up month-by-month with your financial
trend so you can see total household value at a glance.

### 🔔 Gentle monthly reminder
Optional local notification on the 1st of each month: *"Time to update your assets."*
No push servers, no account required.

### 🌐 Ships in English and 简体中文
Every string goes through Apple's String Catalog from day one, so currencies, dates, and
pluralization all follow your locale. Override the app language independently of the
system if you like.

## 🔒 Privacy by design

- **Your data never leaves your Mac.** Storage is a local-only SwiftData store in the
  app sandbox. CloudKit sync is intentionally **off**.
- **The only network call is fetching public FX rates** — no user data, no analytics,
  no ad SDKs, no account system.
- **Portable, human-readable backups.** Export your whole store to a single `.cairn`
  JSON file from **Settings → Backup → Export**. Drop it in iCloud Drive, Dropbox, or
  a Git repo to carry between Macs, or just to keep a personal archive.

## 📦 Install

Cairn is open-source and has no Apple Developer account behind it, so there are no
signed App Store builds.

- **macOS** — grab the latest `Cairn-x.y.z.dmg` from the
  [Releases page](../../releases), drag it to `/Applications`. The first launch needs
  `Control-click → Open` because the build is ad-hoc signed.
- **iOS / iPadOS** — open the project in Xcode, sign it with your free Personal Team,
  and run on your device. See the [Development Guide](docs/development.md).
- **Build from source** — see the [Development Guide](docs/development.md).

System requirements: **macOS 14 Sonoma** or **iOS / iPadOS 17** or later.

## 🗺 Status & Roadmap

Cairn is early-stage. macOS is the primary distribution target; iOS / iPadOS now run
the full app with adapted navigation (bottom tabs, swipeable Overview).

- **v1** — Members (with avatars) · Accounts · Holdings · Monthly snapshots · FX ·
  Trend chart · Physical assets · Backup · iOS / iPadOS support
- **v1.1** — CSV export, Face ID / Touch ID lock
- **v2+** — Depreciation rules, quote API, Widgets, Siri Shortcuts

Full spec: [PRD.md](PRD.md).

## 📚 Documentation

- [Product spec (PRD)](PRD.md)
- [Design notes](DESIGN.md)
- [Development guide](docs/development.md) — build, project structure, localization, contributing

## 🤝 Contributing

Pull requests welcome. Start with the [Development Guide](docs/development.md) for the
build workflow, localization rules, and commit conventions.

## 📄 License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

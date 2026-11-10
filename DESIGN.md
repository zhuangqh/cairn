---
version: alpha
name: Cairn Private Bank
description: >-
  Warm ivory ground, ink-green primary, hairline-ruled sections with prominent
  section titles. Cairn should read like a well-kept family monthly statement,
  not a dashboard toy. Light values are normative; "-dark" tokens are
  provisional until a dark design exists.
colors:
  primary: "#2D5A47"
  primary-active: "#234737"
  secondary: "#A8834A"
  neutral: "#F7F6F2"
  surface: "#FFFFFF"
  on-surface: "#1E2A24"
  error: "#FF3B30"
  ink: "#1E2A24"
  ink-secondary: "#5F6862"
  ink-tertiary: "#8D948F"
  line: "rgba(30, 42, 36, 0.12)"
  primary-tint: "#C9D6CC"
  primary-soft: "rgba(45, 90, 71, 0.08)"
  track: "rgba(30, 42, 36, 0.07)"
  thumb: "#EEEBE3"
  placeholder: "#B7BBB6"
  brass-soft: "rgba(168, 131, 74, 0.14)"
  mist: "#6F8796"
  terracotta: "#B4775A"
  brick: "#B5523B"
  segment-thumb: "#FDFCF9"
  tab-glass: "rgba(251, 250, 246, 0.74)"
  avatar-green: "#DCE5DF"
  avatar-green-ink: "#2D5A47"
  avatar-sand: "#EAE5DA"
  avatar-sand-ink: "#6B604B"
  avatar-slate: "#DFE3E8"
  avatar-slate-ink: "#4F5D6A"
  avatar-rose: "#E8E0DD"
  avatar-rose-ink: "#6E5852"
  neutral-dark: "#131614"
  surface-dark: "#1C201D"
  ink-dark: "#ECEDE8"
  ink-secondary-dark: "#A6ADA8"
  ink-tertiary-dark: "#7C847F"
  line-dark: "rgba(236, 237, 232, 0.12)"
  primary-dark: "#7FB59A"
  primary-active-dark: "#6A9C83"
  primary-tint-dark: "#3B5146"
  primary-soft-dark: "rgba(127, 181, 154, 0.14)"
  track-dark: "rgba(236, 237, 232, 0.08)"
  thumb-dark: "#222723"
  placeholder-dark: "#5E6560"
  secondary-dark: "#CDAA6E"
  brass-soft-dark: "rgba(205, 170, 110, 0.16)"
  mist-dark: "#9AB0BE"
  terracotta-dark: "#D49A7E"
  brick-dark: "#E08A72"
typography:
  headline-display:
    fontFamily: SF Pro
    fontSize: 32px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: -0.02em
  headline-md:
    fontFamily: SF Pro
    fontSize: 20px
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: -0.01em
  title-nav:
    fontFamily: SF Pro
    fontSize: 17px
    fontWeight: 600
    lineHeight: 1.3
  hero-amount:
    fontFamily: SF Pro
    fontSize: 46px
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: -0.025em
    fontFeature: '"tnum" 1'
  hero-currency:
    fontFamily: SF Pro
    fontSize: 19px
    fontWeight: 600
    lineHeight: 1.05
  delta:
    fontFamily: SF Pro
    fontSize: 15px
    fontWeight: 600
    lineHeight: 1.3
    fontFeature: '"tnum" 1'
  body-md:
    fontFamily: SF Pro
    fontSize: 15.5px
    fontWeight: 400
    lineHeight: 1.35
  amount-md:
    fontFamily: SF Pro
    fontSize: 15.5px
    fontWeight: 500
    lineHeight: 1.35
    fontFeature: '"tnum" 1'
  label-eyebrow:
    fontFamily: SF Pro
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.3
  label-sm:
    fontFamily: SF Pro
    fontSize: 13px
    fontWeight: 500
    lineHeight: 1.3
    fontFeature: '"tnum" 1'
  caption:
    fontFamily: SF Pro
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.3
  label-code:
    fontFamily: SF Mono
    fontSize: 10.5px
    fontWeight: 600
    lineHeight: 1
spacing:
  page-margin: 22px
  section-top: 20px
  title-gap: 8px
  row-height: 48px
  column-gap: 12px
  leading-column: 36px
  share-column: 44px
  ledger-balance-column: 112px
  ledger-change-column: 76px
  meter-gap: 8px
  showcase-tile: 140px
  floating-bar-inset: 116px
rounded:
  bar: 2px
  tag: 6px
  chip: 7px
  segment: 9px
  field: 10px
  glyph-tile: 10px
  badge: 11px
  thumbnail: 14px
  full: 9999px
components:
  section-title:
    textColor: "{colors.ink}"
    typography: "{typography.headline-md}"
  hero-amount:
    textColor: "{colors.ink}"
    typography: "{typography.hero-amount}"
  hero-currency-chip:
    textColor: "{colors.ink-secondary}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.chip}"
    padding: 4px 8px
  currency-code-tag:
    textColor: "{colors.ink-secondary}"
    typography: "{typography.label-code}"
    rounded: "{rounded.tag}"
    width: 36px
    height: 22px
  list-row:
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    height: "{spacing.row-height}"
  list-row-amount:
    textColor: "{colors.ink}"
    typography: "{typography.amount-md}"
  composition-bar-financial:
    backgroundColor: "{colors.primary}"
    rounded: "{rounded.bar}"
    height: 8px
  composition-bar-physical:
    backgroundColor: "{colors.primary-tint}"
    rounded: "{rounded.bar}"
    height: 8px
  progress-meter-track:
    backgroundColor: "{colors.track}"
    rounded: "{rounded.full}"
    height: 3px
  progress-meter-fill:
    backgroundColor: "{colors.primary}"
    rounded: "{rounded.full}"
    height: 3px
  hairline:
    backgroundColor: "{colors.line}"
    height: 0.5px
  caption-text:
    textColor: "{colors.ink-tertiary}"
    typography: "{typography.caption}"
  delta-up-zh:
    textColor: "{colors.brick}"
    typography: "{typography.delta}"
  delta-down-zh:
    textColor: "{colors.primary}"
    typography: "{typography.delta}"
  delta-up:
    textColor: "{colors.primary}"
    typography: "{typography.delta}"
  delta-down:
    textColor: "{colors.brick}"
    typography: "{typography.delta}"
  delta-flat:
    textColor: "{colors.ink-secondary}"
    typography: "{typography.delta}"
  category-swatch:
    rounded: 2.5px
    size: 9px
  category-swatch-real-estate:
    backgroundColor: "{colors.primary}"
  category-swatch-stocks:
    backgroundColor: "{colors.mist}"
  category-swatch-cash:
    backgroundColor: "{colors.secondary}"
  category-swatch-devices:
    backgroundColor: "{colors.terracotta}"
  glyph-tile:
    rounded: "{rounded.glyph-tile}"
    size: 38px
  range-picker-option-selected:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.ink}"
    rounded: 8px
    padding: 5px 9px
  range-picker-option:
    textColor: "{colors.ink-secondary}"
    padding: 5px 9px
  segmented-control:
    backgroundColor: "rgba(30, 42, 36, 0.06)"
    rounded: "{rounded.segment}"
    padding: 2px
  segmented-control-selected:
    backgroundColor: "{colors.segment-thumb}"
    textColor: "{colors.ink}"
    rounded: 7px
  input-field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.amount-md}"
    rounded: "{rounded.field}"
  input-field-placeholder:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.placeholder}"
    typography: "{typography.amount-md}"
    rounded: "{rounded.field}"
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
    rounded: "{rounded.full}"
  button-primary-pressed:
    backgroundColor: "{colors.primary-active}"
    textColor: "{colors.surface}"
    rounded: "{rounded.full}"
  showcase-tile:
    backgroundColor: "{colors.thumb}"
    rounded: "{rounded.thumbnail}"
    width: "{spacing.showcase-tile}"
    height: 104px
  trend-line:
    textColor: "{colors.primary}"
    size: 2.2px
  trend-snapshot-dot:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    size: 7px
  trend-now-dot:
    backgroundColor: "{colors.secondary}"
    size: 9px
  avatar:
    backgroundColor: "{colors.avatar-green}"
    textColor: "{colors.avatar-green-ink}"
    rounded: "{rounded.full}"
    size: 28px
  avatar-sand:
    backgroundColor: "{colors.avatar-sand}"
    textColor: "{colors.avatar-sand-ink}"
  avatar-slate:
    backgroundColor: "{colors.avatar-slate}"
    textColor: "{colors.avatar-slate-ink}"
  avatar-rose:
    backgroundColor: "{colors.avatar-rose}"
    textColor: "{colors.avatar-rose-ink}"
  tab-bar:
    backgroundColor: "{colors.tab-glass}"
    rounded: "{rounded.full}"
    height: 60px
  tab-item-selected:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary}"
---

# Cairn Design System: "Private Bank"

This file follows the [DESIGN.md specification](https://stitch.withgoogle.com/docs/design-md/specification)
(version `alpha`). The front matter tokens are normative; the prose explains how
to apply them. Token dimensions are written in `px` as the format requires; on
Apple platforms read 1px as 1pt. Component variants (`-pressed`, `-selected`,
`-placeholder`, per-hue and per-language deltas) follow the spec's sibling-key
convention. Check the file with `npx -p @google/design.md designmd lint docs/design.md`. Repository-wide layout and accessibility rules live in
[AGENTS.md](AGENTS.md); the screenshot and visual-review workflow lives in
[development.md](docs/development.md).

## Overview

Cairn is a local-first family net-worth app. Its visual system, code-named
**Private Bank**, should feel professional, refined, and trustworthy, like a
well-written family monthly statement rather than a gamified dashboard.

- **Data comes first.** Data surfaces stay quiet and flat, with no shadows and
  no floating cards. Hierarchy comes from only three things: type size and
  weight, whitespace, and hairlines.
- **One primary, a few accents, each with one job.** Ink green is the primary
  for interaction and selection. Brass marks achievements and "now". Gain and
  loss use ink green and brick red, with the language deciding which one means
  a rise. Categories use four muted hues. Text, amounts, and rules stay in
  neutral inks and warm grays.
- **Titles lead.** Every section opens with a 20pt bold title, so the page
  structure reads at a glance.
- **Dense, not cramped.** Rows are 48pt with right-aligned amount columns. Show
  more per screen, but keep every row easy to read.
- **Glass only for floating chrome.** Liquid Glass is reserved for the tab bar,
  floating buttons, and the floating total bar; data surfaces never use it.

The mockups covered iPhone, Simplified Chinese, and light mode. The
implementation has also been checked in English and at large Dynamic Type
sizes. Dark mode, iPad, and macOS layouts are open items (see Open Questions).

## Colors

The palette sits on a warm ivory ground with a deep ink-green primary. Each
accent has a single, narrow role.

- **Ink Green (`primary`, #2D5A47):** Links, selection, progress, and the trend
  line. It is also one side of the gain/loss pair.
- **Brass (`secondary`, #A8834A):** Achievements, milestones, and "now"
  markers, such as the latest-achievement label, the next-milestone amount,
  journey dots, and the trend chart's end point. It is also the cash category
  hue. Brass never marks interaction or gain/loss.
- **Warm Ivory (`neutral`, #F7F6F2):** The page ground. Data sits directly on it.
- **Ink (`ink`, #1E2A24):** Primary text, titles, and amounts. `ink-secondary`
  is for labels and unselected controls; `ink-tertiary` is for captions,
  shares, axis labels, and chevrons only, never for key values.
- **Hairline (`line`):** 0.5pt section and row separators and 1pt outlines.
- **Primary active (`primary-active`, #234737):** The pressed state of
  `primary`-filled buttons.
- **Primary tint, soft, and track:** `primary-tint` is the second segment of
  two-part bars, `primary-soft` is selection grounds, and `track` is empty
  meter rails.
- **Thumb (`thumb`, #EEEBE3):** The ground behind possession photos.
- **Field (`surface`, #FFFFFF):** Input fields.

### Category hues

Four hues with matching lightness and saturation are assigned **per category,
not by rank**. A category therefore has the same color everywhere: composition
swatches, account icon tiles, and possession tiles. Icon tiles use the hue at
12% opacity as the ground and the full hue for the glyph. Beyond four
categories, merge into "Other" instead of adding hues.

| Hue | Account kind | Possession category |
| --- | --- | --- |
| Ink Green `primary` | Real estate | Real estate |
| Mist `mist` | Stocks | Vehicles |
| Brass `secondary` | Cash | Other |
| Terracotta `terracotta` | Devices | Electronics |

### Gain and loss

- Direction is always carried by an arrow: ↗ for a rise, ↘ for a fall. Flat
  values have no arrow and use `ink-secondary`.
- Color follows the interface language. In code, `ChangeTone` is the only
  source of these colors.
  - **Chinese (`zh`):** red rises, green falls. A rise uses `brick`
    and a fall uses `primary`.
  - **Other languages:** green rises, red falls. A rise uses `primary` and a
    fall uses `brick`.
- This applies to hero deltas, the ledger "Change" column, snapshot detail
  changes, and entry-form month-over-month hints.
- Errors and failed validation keep the system red (`error`), never `brick`,
  so they are not confused with market moves.
- `brick` has about 4.6:1 contrast on `neutral`.
- `primary-soft`, `brass-soft`, `track`, and `line` are translucent and always
  sit on `neutral`. Judge contrast against the composited ground (for example,
  `primary` on `primary-soft` over `neutral` is about 6.5:1). The linter compares
  against the raw translucent value and reports false contrast warnings for
  `range-picker-option-selected` and `tab-item-selected`.
- `placeholder` is deliberately low-contrast (about 1.9:1 on `surface`). It
  marks a suggested value (last month's) that the user has not entered, never
  information the user must read.

### Avatars

Member avatars without photos use a low-saturation ground with a deeper letter
of the same hue: green, sand, slate, or rose (`avatar-*` tokens). The tone is
assigned from the member ID so it stays stable across launches. Never use
saturated blue or pink.

### Dark mode

The `-dark` tokens are a provisional counterpart: a warm near-black ground and
a lifted ink green that keeps the primary recognizable and legible. They are
not an inversion of the light palette and have not been through full visual
review.

## Typography

The system font is used throughout: SF Pro with PingFang for Chinese. All
figures use monospaced (tabular) digits. Currency codes and FX rates use
SF Mono.

- **Page title (`headline-display`):** 32pt bold with tight tracking.
- **Section title (`headline-md`):** 20pt bold. Every section starts with one.
- **Hero amount (`hero-amount`):** 46pt semibold, scaled relative to Large
  Title. The currency symbol (`hero-currency`, 19pt) sits on the same baseline
  and follows the locale's symbol position.
- **Delta line (`delta`):** 15pt semibold values with a regular `ink-secondary`
  caption.
- **Rows (`body-md`, `amount-md`):** 15.5pt regular names and 15.5pt medium
  amounts.
- **Eyebrows, captions, and table headers (`label-eyebrow`, `label-sm`,
  `caption`):** 12–14pt in `ink-secondary` or `ink-tertiary`.
- Every size follows Dynamic Type. When space runs out, wrap first; never
  shrink text. A single-token value such as an amount stays whole rather than
  breaking mid-number. At xxLarge and above, ledger months use the abbreviated
  form ("Nov 2026") so they wrap on word boundaries.
- Tighten tracking only at large sizes; body text keeps 0.

### Numbers and formatting

- **Summary figures** (hero, section totals, share rows, category amounts) show
  whole units, such as `US$1,180,918`.
- **Detail figures** (ledger, snapshot entries, holding input) keep the
  currency's minor units, such as `13,500.00`. Precision is consistent within a
  column.
- These rules are display-only. They never change stored `Decimal` precision
  and never hide significant digits to fit a column.
- Chart axis labels may use compact notation (`US$1.2M`, `US$120万`).
- Format amounts and dates with locale-aware formatters, never by string
  concatenation.
- Percentages carry no `+` sign; the arrow conveys direction. Ledger changes
  carry a sign (`+300.00`, `−300.00`).

## Layout

The layout is a single 22pt leading guide (`page-margin`) shared by every
title, row, and hairline on iPhone; macOS uses 24pt.

- **Sections:** A 0.5pt `line` rule on top, 20pt before the title
  (`section-top`), and 8pt between title and content (`title-gap`). No extra
  spacing between sections. The title row holds at most one trailing action: a
  link ("All ›", "Details ›", "Edit ›"), a year filter ("⚟ 2026"), a range
  picker, or `ink-tertiary` meta text. When the title and action don't fit,
  the header reflows onto two lines.
- **Rows:** At least 48pt tall (`row-height`), separated by 0.5pt hairlines
  that start at the content column, aligned with the leading icon column.
- **Columns:** Rows use fixed column widths. The leading mark column is 36pt,
  the share column 44pt, and the gap 12pt. Related values share one set of
  widths through `Grid` or shared metrics; never nudge individual rows. Ledger
  rows use month / balance (112pt) / change (76pt), scaled with Dynamic Type.
- **Progress rows:** The meter starts at the name column, runs to the row end,
  and sits 8pt below the text so it doesn't read as an underline.
- **Wide macOS dashboard:** Two equal columns sharing one guide: hero beside the
  journal panel, then trend beside composition, then the members line across
  both.
- **Floating chrome:** Leave room at the bottom for the floating tab bar and let
  scroll edges fade into the ground rather than drawing a hard rule.

## Elevation & Depth

The system is flat. Depth comes from type, whitespace, and hairlines, not
shadows or tonal cards.

- Data sections sit directly on `neutral` with no card ground, shadow, or
  gradient. The hero is separated from the first section only by a hairline.
- The only raised elements are floating chrome: the tab bar, floating buttons,
  and the floating total bar on the batch-entry sheet. They use Liquid Glass on
  iOS/macOS 26 and fall back to a solid ground with a hairline outline on older
  systems or when Reduce Transparency is on.
- The selected thumb of the page-level segmented control is the one in-content
  exception: `segment-thumb` with a barely visible 1pt shadow.

## Shapes

Shapes are softly squared with small radii. The few rounded elements read as
tags and tiles, not cards.

- Currency code tags use 6pt corners (`rounded.tag`), with a 1pt `line`
  outline.
- Hero currency chips use 7pt corners (`rounded.chip`), with a 1pt `line`
  outline.
- Composition bars use 2pt corners, with a 3pt gap between segments.
- Input fields use 10pt corners. The outline is 1pt `line`, or 1.5pt `primary`
  when focused.
- Glyph tiles use 10pt corners on 38pt (about 26% of their size).
- Achievement badges use 11pt and possession thumbnails use 14pt.
- Capsules (`rounded.full`) are reserved for meters, the primary sheet
  button, avatars, and the tab bar.
- The macOS sidebar shows the app icon artwork clipped to a 9pt continuous
  corner on a 38pt tile.

## Components

- **Hero summary:** From top to bottom: an eyebrow row with the label on the
  left and the currency chip on the right; the amount with the currency symbol
  on the amount's baseline; the delta line (`↗ US$3,300  0.3%  vs last month`,
  colored per Gain and loss); and a 13pt `ink-tertiary` date or meta line. It
  has no card ground.
- **Composition:** A two-segment bar (financial `primary`, physical
  `primary-tint`), 8pt tall. The legend sits at both ends with bold
  percentages. Below it, category rows in a four-column `Grid`: 9pt category
  swatch / name / share (`ink-tertiary`) / amount.
- **Progress rows (by member, by currency):** Leading avatar or currency tag /
  name with an inline caption / amount / share, with the meter below.
- **Ledger:** A single-line, three-column table (month / balance / change)
  under a light 12pt header that names the unit, such as "Balance (US$)". The
  first entry's change reads "First record" in `ink-tertiary`.
- **Currency code tag:** 36×22pt, SF Mono 10.5pt semibold, `ink-secondary`.
  Flags are never used.
- **Range picker:** Text-only buttons (6M / 1Y / 2Y / 5Y) in the section header.
  The selected option gets a `primary-soft` ground and semibold weight.
- **Segmented control (Financial / Physical):** A 6% `ink` track with a raised
  `segment-thumb`.
- **Trend chart:**
  - A monotone cubic line (2.2pt `primary`) that never overshoots real values,
    over a flat 10% `primary` fill with no gradient.
  - Three horizontal gridlines (zero, midpoint, maximum), with only the maximum
    labeled, at the top left.
  - At most three x-axis ticks: the first leading-aligned, the last
    trailing-aligned, the middle centered. The year shows only on the first
    tick and when it changes. Labels never overlap; drop ticks instead of
    shrinking text.
  - **Snapshot dots:** Months with a captured snapshot get a 7pt hollow dot on
    the curve, with a `neutral` fill and a 1.5pt `primary` ring. Beyond 24
    months, they become 4pt solid `primary` dots.
  - **Now dot:** A 9pt `secondary` (brass) dot with a 2pt ground-colored ring,
    drawn on top.
  - The axis header shows "○ Snapshot" before "Month-end". Each dot has a
    VoiceOver label with its month and amount.
- **Navigation rows (members, journal):** The whole row is tappable, with a 7pt
  `ink-tertiary` chevron. The journal row shows a 44pt badge, then "Achievement
  Journal · Latest" above the achievement name and month. Locked badges are
  grayscale at 55% opacity.
- **Showcase:** A horizontally scrolling shelf of 140pt tiles with a 104pt
  `thumb` image well (photos multiplied into the ground), a single-line name,
  and the purchase price in `ink-tertiary`.
- **Settings rows:** A 22pt monochrome line icon in `ink-secondary` / label /
  current value in `ink-secondary`, or `primary` when the value is
  interactive. Section notes go at the end of the section in `ink-tertiary`.
  Toggles use the system style tinted `primary`.
- **Forms and sheets:**
  - Grabber and a centered title. "Cancel" is a text button; the primary action
    is a `primary` capsule.
  - Inputs have an embedded currency-code segment and right-aligned values.
  - Blank and zero must look different: blank shows last month's value as a
    `placeholder` prompt, a carried-forward value renders in solid ink, and a
    user-entered 0 shows as 0.
  - The batch-entry sheet ends with a floating glass total bar: an explanation
    on the left and a 20pt total on the right.
- **Tab bar:** A floating capsule 60pt tall, inset 22pt from the sides and
  26pt from the bottom, in ivory glass with a 0.5pt outline. The selected tab
  uses `primary` for icon and label on a `primary-soft` capsule.

### Motion and accessibility

- Default to critically damped springs (damping 1.0, response 0.3–0.4). Allow
  bounce only after a drag or fling. With Reduce Motion on, use cross-fades.
- Every chart, bar, and badge has a VoiceOver label that reads actual values
  and shares, not just colors.
- Body text keeps at least 4.5:1 contrast with the ground.

## Do's and Don'ts

- Do start every section with a 20pt bold title and a hairline rule.
- Do keep related amounts in shared, trailing-aligned columns with tabular
  digits.
- Do take gain/loss colors from `ChangeTone`, and always pair them with an
  arrow.
- Do give each category its fixed hue everywhere it appears.
- Do wrap before shrinking text, and keep amounts unbroken.
- Don't use flags; use currency code tags.
- Don't use candy colors for categories; use only the four category hues.
- Don't use brass for interactive elements or for gain/loss.
- Don't decorate settings icons with colored tiles.
- Don't add card shadows, gradients, or glass to data surfaces.
- Don't use system red for market moves, or `brick` for errors.

## Implementation

- Tokens live in `Cairn/Shared/UI/GlassCardStyle.swift`. The Swift names map to
  the tokens above:
  - `pageBackground` = `neutral`
  - `ink`, `ink2`, `ink3` = `ink`, `ink-secondary`, `ink-tertiary`
  - `accent`, `accentActive`, `accent2`, `accentSoft` = `primary`,
    `primary-active`, `primary-tint`, `primary-soft`
  - `brass`, `brassSoft` = `secondary`, `brass-soft`
  - `field` = `surface`
  - `mist`, `terracotta`, `brick`, `line`, `track`, `thumb`, `placeholder`
    keep their names.
- Each Swift color carries its light and `-dark` values. The remaining
  `notion…` names are transitional aliases mapped into this palette; don't use
  them in new code.
- Shared components:
  - `Cairn/Shared/UI/LedgerComponents.swift`: sections, hairlines, rows,
    currency code tags, progress rows, composition bars, glyph tiles, and the
    range picker.
  - `Cairn/Shared/UI/LedgerHero.swift`: the hero summary, baseline-split amount,
    delta line, and detail-figure formatting.
  - `Cairn/Shared/UI/LedgerSegmentedControl.swift`: the page-level segmented
    control.
  - `Cairn/Features/Assets/TrendChartView+Marks.swift`: trend snapshot dots,
    the now dot, and axis ticks.

## Open Questions

- **Dark mode:** Not formally designed. The `-dark` tokens keep the UI legible
  but haven't had full visual review.
- **iPad and macOS:** Sidebar layout, multi-column grids, and how wide amount
  columns should get on large screens.
- **Tab bar:** Currently the system TabView tinted `primary`, not yet the
  ivory-glass capsule described above.
- **Hero band:** A very light, flat ink-green band behind the hero (for example
  `#EEF2EC`) could anchor color on the page. It needs a page-margin structure
  change and is not implemented.

## Reference Mockups

The HTML mockups live locally in `build/design-mockups/`, which is not under
version control:

- `a-v2.html`: dashboard, financial assets, account detail.
- `a-v2-round2.html`: possessions, achievement journal, members, settings, and
  the add-snapshot form.
- `index.html`: archive of the first-round comparison of directions A (Private
  Bank), B (Swiss data terminal), and C (refined Apple-native).

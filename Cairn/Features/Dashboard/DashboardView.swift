import SwiftUI
import SwiftData

/// Home screen of the app. A redesigned, typography-driven layout that
/// answers three questions in order: *how much are we worth*, *what is
/// driving that number*, and *where is it allocated*.
///
/// Sections (top → bottom):
///   1. **Hero** — headline total + signed monthly delta + composition hint.
///   2. **Composition** — financial vs physical split with a stacked bar
///      and per-segment value / share / delta.
///   3. **Trend** — monthly net-worth chart (financial line + physical
///      overlay), drives time-travel via hover.
///   4. **Allocation** — donut + detailed per-category list with value,
///      share, and signed change.
///
/// Hovering a point on the trend chart time-travels every other section
/// to that month. Cards use the Notion-style flat surface (`glassCard`)
/// to keep the visual rhythm minimal — depth comes from typography and
/// hierarchy, not borders.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    // Query sentinels — touch .count in computed vars so @Query invalidates totals.
    @Query private var holdings: [Holding]
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]
    @Query private var members: [Member]
    @Query private var assets: [Asset]

    /// Current hover selection from the embedded trend chart. When set, the
    /// hero / composition / allocation cards render values as of that month.
    @State private var hoverSelection: TrendSelection?

    // MARK: - Derivation

    /// Single render-pass aggregate. Bundles every figure the layout needs
    /// — current + previous-month totals, per-segment splits, per-kind
    /// allocation, and per-kind delta — so the FX rate cache and snapshot
    /// index are loaded exactly once per body invocation regardless of how
    /// many cards consume the data.
    private struct Derivation {
        var financial: Decimal
        var physical: Decimal
        var combined: Decimal

        var financialPrev: Decimal
        var physicalPrev: Decimal
        var combinedPrev: Decimal

        var allocation: [NetWorthCalculator.KindTotal]
        var allocationByKind: [AccountKind: Decimal]
        var allocationByKindPrev: [AccountKind: Decimal]

        var missingCurrencies: [String]

        /// Convenience: signed percentage change vs prior month, or nil when
        /// the prior period has no baseline.
        static func deltaPercent(current: Decimal, previous: Decimal) -> Double? {
            guard previous != 0 else { return nil }
            let change = (current - previous) / previous
            return NSDecimalNumber(decimal: change).doubleValue
        }
    }

    private func derive() -> Derivation {
        // Touch the @Query sentinels so SwiftUI invalidates this view when
        // any upstream model changes.
        _ = holdings.count + snapshots.count + rates.count + members.count + assets.count

        let asOf = effectiveAsOf
        let prevAsOf = previousMonth(of: asOf)

        let rateCache = FXService.RateCache.load(in: context)
        let snapshotIndex = NetWorthCalculator.SortedSnapshotIndex.load(in: context)

        let financial = NetWorthCalculator.bundle(
            homeCurrency: homeCurrency,
            asOf: asOf,
            includeMemberBreakdown: false,
            rateCache: rateCache,
            sortedSnapshots: snapshotIndex,
            context: context
        )
        let financialPrev = NetWorthCalculator.bundle(
            homeCurrency: homeCurrency,
            asOf: prevAsOf,
            includeMemberBreakdown: false,
            rateCache: rateCache,
            sortedSnapshots: snapshotIndex,
            context: context
        )
        let physical = AssetService.bundle(
            homeCurrency: homeCurrency,
            asOf: hoverSelection?.period,
            rateCache: rateCache,
            context: context
        )
        let physicalPrev = AssetService.bundle(
            homeCurrency: homeCurrency,
            asOf: prevAsOf,
            rateCache: rateCache,
            context: context
        )

        let mergedMissing = Set(financial.totals.missingCurrencies)
            .union(physical.totals.missingCurrencies)
            .sorted()

        let byKind = mergeByKind(financial: financial.byKind, physical: physical.byCategory)
        let byKindPrev = mergeByKind(financial: financialPrev.byKind, physical: physicalPrev.byCategory)

        let allocation = byKind
            .filter { $0.value != 0 }
            .map { NetWorthCalculator.KindTotal(kind: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        return Derivation(
            financial: financial.totals.amount,
            physical: physical.totals.amount,
            combined: financial.totals.amount + physical.totals.amount,
            financialPrev: financialPrev.totals.amount,
            physicalPrev: physicalPrev.totals.amount,
            combinedPrev: financialPrev.totals.amount + physicalPrev.totals.amount,
            allocation: allocation,
            allocationByKind: byKind,
            allocationByKindPrev: byKindPrev,
            missingCurrencies: mergedMissing
        )
    }

    /// Folds physical-asset categories into the per-kind buckets:
    ///   `realEstate / vehicle      → AccountKind.realEstate`
    ///   `electronics / other       → AccountKind.device`
    private func mergeByKind(
        financial: [NetWorthCalculator.KindTotal],
        physical: [AssetService.CategoryTotal]
    ) -> [AccountKind: Decimal] {
        var byKind: [AccountKind: Decimal] = [:]
        byKind.reserveCapacity(financial.count + physical.count)
        for entry in financial { byKind[entry.kind] = entry.amount }
        for entry in physical {
            let kind: AccountKind
            switch entry.category {
            case .realEstate, .vehicle: kind = .realEstate
            case .electronics, .other:  kind = .device
            }
            byKind[kind, default: 0] += entry.amount
        }
        return byKind
    }

    private func previousMonth(of date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let normalized = Snapshot.normalize(date)
        return calendar.date(byAdding: .month, value: -1, to: normalized) ?? normalized
    }

    // MARK: - Computed

    /// Month the Dashboard should render for. Driven by hover selection when
    /// present, otherwise "now".
    private var effectiveAsOf: Date {
        hoverSelection?.period ?? .now
    }

    // MARK: - Body

    /// Breakpoints for the adaptive layout. Single-column below `compact`,
    /// Breakpoints for the adaptive layout. Single-column below `compact`,
    /// otherwise the wide layout kicks in. At `wide` and up the
    /// composition + allocation cards share a single row.
    private enum Layout {
        static let compact: CGFloat = 560
        static let wide: CGFloat = 880
    }

    var body: some View {
        let derivation = derive()
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < Layout.compact
            let isWide = width >= Layout.wide

            ScrollView {
                VStack(spacing: isCompact ? 18 : 24) {
                    heroCard(isCompact: isCompact, derivation: derivation)
                    trendCard
                    if isWide {
                        HStack(alignment: .top, spacing: 24) {
                            compositionCard(isCompact: isCompact, derivation: derivation)
                                .frame(maxWidth: .infinity)
                            allocationCard(derivation: derivation)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        compositionCard(isCompact: isCompact, derivation: derivation)
                        allocationCard(derivation: derivation)
                    }
                }
                .pageHorizontalPadding()
                .padding(.vertical, 20)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
        }
        .navigationTitle("dashboard.title")
    }

    // MARK: - Hero

    @ViewBuilder
    private func heroCard(isCompact: Bool, derivation: Derivation) -> some View {
        let combinedDeltaPct = Derivation.deltaPercent(
            current: derivation.combined,
            previous: derivation.combinedPrev
        )
        let combinedDeltaAbs = derivation.combined - derivation.combinedPrev

        let amountFont: Font = isCompact
            ? .system(size: 36, weight: .bold)
            : .system(size: 52, weight: .bold)

        VStack(alignment: .leading, spacing: 14) {
            Text("dashboard.totalWealth")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.notionInkSecondary)

            Text(
                derivation.combined,
                format: .currency(code: homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
            .font(amountFont)
            .tracking(isCompact ? -0.5 : -1.5)
            .foregroundStyle(Color.notionInk)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.2), value: derivation.combined)

            if combinedDeltaPct != nil {
                heroDeltaRow(absolute: combinedDeltaAbs, percent: combinedDeltaPct)
            }

            compositionHint(derivation: derivation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: isCompact ? 20 : 28)
    }

    @ViewBuilder
    private func heroDeltaRow(absolute: Decimal, percent: Double?) -> some View {
        let positive = absolute >= 0
        let color: Color = positive ? .notionGreen : .notionOrange
        let arrow = positive ? "arrow.up" : "arrow.down"
        HStack(spacing: 8) {
            Text(CompactCurrencyFormatter.string(
                amount: absolute,
                code: homeCurrency,
                locale: locale,
                alwaysSigned: true
            ))
            .font(.system(size: 15, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)

            if let percent {
                HStack(spacing: 3) {
                    Image(systemName: arrow)
                        .font(.system(size: 11, weight: .bold))
                    Text(percent, format: .percent.precision(.fractionLength(1)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())
            }

            Text("dashboard.vsLastMonth")
                .font(.system(size: 13))
                .foregroundStyle(Color.notionInkSecondary)
        }
    }

    @ViewBuilder
    private func compositionHint(derivation: Derivation) -> some View {
        let total = derivation.combined
        let financialPct = total > 0
            ? NSDecimalNumber(decimal: derivation.financial / total).doubleValue
            : 0
        let physicalPct = max(0, 1 - financialPct)
        if total > 0 {
            HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Color.notionBlue).frame(width: 7, height: 7)
                Text("dashboard.balance.financial")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.notionInkSecondary)
                Text(financialPct, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.notionInk)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.notionTeal).frame(width: 7, height: 7)
                Text("dashboard.balance.physical")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.notionInkSecondary)
                Text(physicalPct, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.notionInk)
            }
        }
        }
    }

    // MARK: - Composition

    /// Replaces the old "balance sheet" two-card row. Renders a single
    /// stacked bar for financial vs physical with per-segment value,
    /// share, and signed delta.
    @ViewBuilder
    private func compositionCard(isCompact: Bool, derivation: Derivation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dashboard.composition")
                .font(.notionCardTitle)
                .tracking(-0.25)
                .foregroundStyle(Color.notionInk)

            stackedBar(derivation: derivation)

            VStack(spacing: 14) {
                compositionRow(
                    titleKey: "dashboard.balance.financial",
                    amount: derivation.financial,
                    previous: derivation.financialPrev,
                    total: derivation.combined,
                    tint: .notionBlue
                )
                Divider().overlay(Color.notionBorder)
                compositionRow(
                    titleKey: "dashboard.balance.physical",
                    amount: derivation.physical,
                    previous: derivation.physicalPrev,
                    total: derivation.combined,
                    tint: .notionTeal
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: isCompact ? 18 : 22)
    }

    @ViewBuilder
    private func stackedBar(derivation: Derivation) -> some View {
        let total = derivation.combined
        GeometryReader { geo in
            HStack(spacing: 2) {
                if total > 0 {
                    let fWidth = max(0, NSDecimalNumber(decimal: derivation.financial / total).doubleValue) * geo.size.width
                    let pWidth = max(0, geo.size.width - fWidth - 2)
                    Rectangle()
                        .fill(Color.notionBlue)
                        .frame(width: fWidth)
                    Rectangle()
                        .fill(Color.notionTeal)
                        .frame(width: pWidth)
                } else {
                    Rectangle()
                        .fill(Color.notionBorder)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    @ViewBuilder
    private func compositionRow(
        titleKey: LocalizedStringKey,
        amount: Decimal,
        previous: Decimal,
        total: Decimal,
        tint: Color
    ) -> some View {
        let pct = total > 0 ? NSDecimalNumber(decimal: amount / total).doubleValue : 0
        let deltaPct = Derivation.deltaPercent(current: amount, previous: previous)
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(tint).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.notionInk)
                Text(pct, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color.notionInkSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(CompactCurrencyFormatter.string(
                    amount: amount,
                    code: homeCurrency,
                    locale: locale
                ))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.notionInk)
                .lineLimit(1)
                if let deltaPct {
                    DeltaBadge(percent: deltaPct)
                }
            }
        }
    }

    // MARK: - Trend

    private var trendCard: some View {
        TrendChartView(
            showAssetOverlay: true,
            onSelectionChange: { selection in
                withAnimation(.easeOut(duration: 0.15)) {
                    hoverSelection = selection
                }
            }
        )
        .glassCard()
    }

    // MARK: - Allocation (donut + categories merged)

    private func allocationCard(derivation: Derivation) -> some View {
        // Build per-kind month-over-month deltas. Skip kinds with no
        // baseline so the badge layer stays semantically meaningful.
        var deltas: [AccountKind: Double] = [:]
        for kind in AccountKind.allCases {
            let curr = derivation.allocationByKind[kind] ?? 0
            let prev = derivation.allocationByKindPrev[kind] ?? 0
            if let pct = Derivation.deltaPercent(current: curr, previous: prev) {
                deltas[kind] = pct
            }
        }
        return VStack(alignment: .leading, spacing: 16) {
            Text("dashboard.allocation")
                .font(.notionCardTitle)
                .tracking(-0.25)
                .foregroundStyle(Color.notionInk)
            AllocationDonutView(
                entries: derivation.allocation,
                homeCurrency: homeCurrency,
                deltas: deltas
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

#if DEBUG
#Preview("Dashboard · seeded") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        DashboardView()
    }
    .modelContainer(PreviewSampleData.container())
}

#Preview("Dashboard · empty") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        DashboardView()
    }
    .modelContainer(PreviewSampleData.emptyContainer())
}
#endif

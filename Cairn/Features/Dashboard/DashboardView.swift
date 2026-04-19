import SwiftUI
import SwiftData

/// Home screen of the app. Shows a hero net-worth card, the monthly trend
/// chart, an allocation donut, and an asset-category breakdown.
///
/// Hovering a point on the trend chart time-travels the hero / portfolio /
/// category cards to that month so the user can inspect historical values
/// without leaving the Dashboard.
///
/// Styled with translucent glass cards against an ambient gradient, mirroring
/// Apple's Liquid Glass design language.
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
    /// hero / allocation / category cards render values as of that month.
    @State private var hoverSelection: TrendSelection?

    // MARK: - Derivation

    /// All numbers the cards need, computed in one pass per body render.
    /// Folds what used to be five independent computed properties (`totals`,
    /// `physicalTotals`, `delta`, `allocation`, `combinedTotals`) into a
    /// single `NetWorthCalculator.Bundle` + `AssetService.Bundle` snapshot
    /// that shares a single FX rate cache and a single sorted-snapshot
    /// index — the previous shape walked every holding 5+ times per render.
    private struct Derivation {
        var totals: NetWorthCalculator.Totals
        var physicalTotals: AssetService.Totals
        var combinedTotals: NetWorthCalculator.Totals
        var allocation: [NetWorthCalculator.KindTotal]
        /// `allocation` indexed by kind, so per-tile lookups don't re-scan.
        var allocationByKind: [AccountKind: Decimal]
        var delta: Double?
    }

    private func derive() -> Derivation {
        // Touch the @Query sentinels so SwiftUI invalidates this view when
        // any upstream model changes.
        _ = holdings.count + snapshots.count + rates.count + members.count + assets.count

        let asOf = effectiveAsOf
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
        let physical = AssetService.bundle(
            homeCurrency: homeCurrency,
            asOf: hoverSelection?.period,
            rateCache: rateCache,
            context: context
        )

        let mergedMissing = Set(financial.totals.missingCurrencies)
            .union(physical.totals.missingCurrencies)
            .sorted()
        let combined = NetWorthCalculator.Totals(
            amount: financial.totals.amount + physical.totals.amount,
            missingCurrencies: mergedMissing
        )

        var byKind: [AccountKind: Decimal] = [:]
        byKind.reserveCapacity(financial.byKind.count)
        for entry in financial.byKind { byKind[entry.kind] = entry.amount }

        return Derivation(
            totals: financial.totals,
            physicalTotals: physical.totals,
            combinedTotals: combined,
            allocation: financial.byKind,
            allocationByKind: byKind,
            delta: financial.monthOverMonthDelta
        )
    }

    // MARK: - Computed

    /// Month the Dashboard should render for. Driven by hover selection when
    /// present, otherwise "now".
    private var effectiveAsOf: Date {
        hoverSelection?.period ?? .now
    }

    // MARK: - Body

    /// Breakpoints for the adaptive layout. Chosen to match common macOS
    /// window sizes: below `compact` we collapse all multi-column rows into a
    /// single column; below `regular` we drop hero / allocation side-by-side
    /// layouts but keep a 2-up category grid.
    private enum Layout {
        static let compact: CGFloat = 560
        static let regular: CGFloat = 820
    }

    var body: some View {
        let derivation = derive()
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < Layout.compact
            let isRegular = width < Layout.regular

            ScrollView {
                VStack(spacing: isCompact ? 16 : 20) {
                    heroCard(isCompact: isCompact, derivation: derivation)
                    balanceSheetCard(isCompact: isCompact, derivation: derivation)
                    trendCard
                    sideBySideCards(isRegular: isRegular, isCompact: isCompact, derivation: derivation)
                }
                .padding(isCompact ? 16 : 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
        }
        .navigationTitle("dashboard.title")
    }

    /// Allocation + Categories lay out side-by-side at regular widths and
    /// stack vertically when the window is narrow.
    @ViewBuilder
    private func sideBySideCards(isRegular: Bool, isCompact: Bool, derivation: Derivation) -> some View {
        if isRegular {
            VStack(spacing: isCompact ? 16 : 20) {
                allocationCard(derivation: derivation)
                categoriesCard(isCompact: isCompact, derivation: derivation)
            }
        } else {
            HStack(alignment: .top, spacing: 20) {
                allocationCard(derivation: derivation)
                    .frame(maxWidth: .infinity)
                categoriesCard(isCompact: isCompact, derivation: derivation)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func heroCard(isCompact: Bool, derivation: Derivation) -> some View {
        heroInfo(isCompact: isCompact, derivation: derivation)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16, padding: isCompact ? 20 : 24)
    }

    @ViewBuilder
    private func heroInfo(isCompact: Bool, derivation: Derivation) -> some View {
        let amountFont: Font = isCompact
            ? .system(size: 34, weight: .bold)
            : .system(size: 48, weight: .bold)
        VStack(alignment: .leading, spacing: 8) {
            Text("dashboard.totalWealth")
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.125)
                .textCase(.uppercase)
                .foregroundStyle(Color.notionInkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(
                    derivation.combinedTotals.amount,
                    format: .currency(code: homeCurrency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(amountFont)
                .tracking(isCompact ? -0.5 : -1.5)
                .foregroundStyle(Color.notionInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: derivation.combinedTotals.amount)

                if let delta = derivation.delta {
                    deltaBadge(delta)
                }
            }
        }
    }

    private func deltaBadge(_ value: Double) -> some View {
        let positive = value >= 0
        let arrow = positive ? "arrow.up.right" : "arrow.down.right"
        let color: Color = positive ? .notionGreen : .notionOrange
        let badgeBg: Color = positive
            ? Color.notionGreen.opacity(0.12)
            : Color.notionOrange.opacity(0.12)
        return HStack(spacing: 4) {
            Image(systemName: arrow)
            Text(value, format: .percent.precision(.fractionLength(0)))
        }
        .font(.system(size: 12, weight: .semibold))
        .tracking(0.125)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeBg, in: Capsule())
    }

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

    // MARK: - Balance sheet (financial + physical)

    /// Compact card that splits the family's holdings between
    /// "Financial" (holdings-based net worth, valued `asOf` the hover month)
    /// and "Physical" (non-sold `Asset` records, valued at their current /
    /// purchase price). Provides a quick mental split that the hero alone —
    /// which reflects financial only — does not.
    @ViewBuilder
    private func balanceSheetCard(isCompact: Bool, derivation: Derivation) -> some View {
        let physical = derivation.physicalTotals
        let financial = derivation.totals
        Group {
            if isCompact {
                VStack(spacing: 12) {
                    balanceTile(
                        titleKey: "dashboard.balance.financial",
                        amount: financial.amount,
                        iconName: "chart.line.uptrend.xyaxis",
                        tint: .notionBlue
                    )
                    balanceTile(
                        titleKey: "dashboard.balance.physical",
                        amount: physical.amount,
                        iconName: "house.and.flag",
                        tint: .notionTeal
                    )
                }
            } else {
                HStack(spacing: 16) {
                    balanceTile(
                        titleKey: "dashboard.balance.financial",
                        amount: financial.amount,
                        iconName: "chart.line.uptrend.xyaxis",
                        tint: .notionBlue
                    )
                    .frame(maxWidth: .infinity)
                    balanceTile(
                        titleKey: "dashboard.balance.physical",
                        amount: physical.amount,
                        iconName: "house.and.flag",
                        tint: .notionTeal
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: isCompact ? 16 : 20)
    }

    private func balanceTile(
        titleKey: LocalizedStringKey,
        amount: Decimal,
        iconName: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: iconName)
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .tracking(0.125)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(
                    amount,
                    format: .currency(code: homeCurrency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: amount)
            }
            Spacer(minLength: 0)
        }
    }

    private func allocationCard(derivation: Derivation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dashboard.portfolioAllocation")
                .font(.notionCardTitle)
                .tracking(-0.25)
                .foregroundStyle(Color.notionInk)
            AllocationDonutView(entries: derivation.allocation, homeCurrency: homeCurrency)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func categoriesCard(isCompact: Bool, derivation: Derivation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dashboard.assetCategories")
                .font(.headline)
            let kinds = AccountKind.allCases
            let columns: [GridItem] = isCompact
                ? [GridItem(.flexible(), spacing: 12)]
                : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(
                columns: columns,
                spacing: 12
            ) {
                ForEach(kinds, id: \.self) { kind in
                    categoryTile(for: kind, derivation: derivation)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func categoryTile(for kind: AccountKind, derivation: Derivation) -> some View {
        let amount = derivation.allocationByKind[kind] ?? 0
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind.tint.opacity(0.15))
                Image(systemName: kind.iconName)
                    .foregroundStyle(kind.tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(kind.localizationKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(
                    amount,
                    format: .currency(code: homeCurrency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: amount)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.notionSurfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.notionBorder, lineWidth: 1)
        )
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

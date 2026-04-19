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

    @State private var isUpdating: Bool = false
    /// Current hover selection from the embedded trend chart. When set, the
    /// hero / allocation / category cards render values as of that month.
    @State private var hoverSelection: TrendSelection?

    // MARK: - Computed

    /// Month the Dashboard should render for. Driven by hover selection when
    /// present, otherwise "now".
    private var effectiveAsOf: Date {
        hoverSelection?.period ?? .now
    }

    private var totals: NetWorthCalculator.Totals {
        _ = holdings.count + snapshots.count + rates.count
        return NetWorthCalculator.total(
            homeCurrency: homeCurrency,
            asOf: effectiveAsOf,
            context: context
        )
    }

    /// Physical-asset total in home currency, valued as of the hovered
    /// month so the Physical tile time-travels in step with the financial
    /// hero. Historical physical values fall back to `purchasePrice` because
    /// we do not persist per-month revaluations for assets.
    private var physicalTotals: AssetService.Totals {
        _ = assets.count + rates.count
        return AssetService.total(
            homeCurrency: homeCurrency,
            asOf: hoverSelection?.period,
            context: context
        )
    }

    /// Sum of financial (holdings) and physical (assets) totals — what the
    /// hero card shows as "Total family wealth". Missing FX currencies from
    /// either side are merged for the warning footnote.
    private var combinedTotals: NetWorthCalculator.Totals {
        let financial = totals
        let physical = physicalTotals
        let merged = Set(financial.missingCurrencies).union(physical.missingCurrencies)
        return NetWorthCalculator.Totals(
            amount: financial.amount + physical.amount,
            missingCurrencies: merged.sorted()
        )
    }

    private var delta: Double? {
        _ = holdings.count + snapshots.count + rates.count
        return NetWorthCalculator.monthOverMonthDelta(
            homeCurrency: homeCurrency,
            asOf: effectiveAsOf,
            context: context
        )
    }

    private var allocation: [NetWorthCalculator.KindTotal] {
        _ = holdings.count + snapshots.count + rates.count
        return NetWorthCalculator.totalsByKind(
            homeCurrency: homeCurrency,
            asOf: effectiveAsOf,
            context: context
        )
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
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < Layout.compact
            let isRegular = width < Layout.regular

            ScrollView {
                VStack(spacing: isCompact ? 16 : 20) {
                    heroCard(isCompact: isCompact)
                    balanceSheetCard(isCompact: isCompact)
                    trendCard
                    sideBySideCards(isRegular: isRegular, isCompact: isCompact)
                }
                .padding(isCompact ? 16 : 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
        }
        .navigationTitle("dashboard.title")
        .sheet(isPresented: $isUpdating) {
            BatchEntryView()
        }
    }

    /// Allocation + Categories lay out side-by-side at regular widths and
    /// stack vertically when the window is narrow.
    @ViewBuilder
    private func sideBySideCards(isRegular: Bool, isCompact: Bool) -> some View {
        if isRegular {
            VStack(spacing: isCompact ? 16 : 20) {
                allocationCard
                categoriesCard(isCompact: isCompact)
            }
        } else {
            HStack(alignment: .top, spacing: 20) {
                allocationCard
                    .frame(maxWidth: .infinity)
                categoriesCard(isCompact: isCompact)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func heroCard(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 16) {
                    heroInfo(isCompact: true)
                    heroAddButton(isCompact: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    heroInfo(isCompact: false)
                    Spacer()
                    heroAddButton(isCompact: false)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: isCompact ? 20 : 24)
    }

    @ViewBuilder
    private func heroInfo(isCompact: Bool) -> some View {
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
                    combinedTotals.amount,
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
                .animation(.easeOut(duration: 0.2), value: combinedTotals.amount)

                if let delta {
                    deltaBadge(delta)
                }
            }
        }
    }

    private func heroAddButton(isCompact: Bool) -> some View {
        Button {
            isUpdating = true
        } label: {
            Label {
                Text("dashboard.addAsset")
            } icon: {
                Image(systemName: "plus")
            }
        }
        .buttonStyle(NotionPrimaryButtonStyle(size: isCompact ? .regular : .large))
        .disabled(holdings.isEmpty)
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
            Text(value, format: .percent.precision(.fractionLength(1)))
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
    private func balanceSheetCard(isCompact: Bool) -> some View {
        let physical = physicalTotals
        let financial = totals
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

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dashboard.portfolioAllocation")
                .font(.notionCardTitle)
                .tracking(-0.25)
                .foregroundStyle(Color.notionInk)
            AllocationDonutView(entries: allocation, homeCurrency: homeCurrency)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func categoriesCard(isCompact: Bool) -> some View {
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
                    categoryTile(for: kind)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func categoryTile(for kind: AccountKind) -> some View {
        let amount = allocation.first { $0.kind == kind }?.amount ?? 0
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

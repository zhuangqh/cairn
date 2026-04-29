import SwiftUI
import SwiftData

/// Trend-focused view: net worth hero, multi-month chart, per-member breakdown.
/// Complements the Dashboard (which emphasizes allocation + activity).
///
/// Hosts a segmented tab at the top so the user can flip between the
/// existing trend view and a dedicated "Assets" tab that manages physical
/// assets (PRD §4.7, v1.1).
struct OverviewView: View {
    enum Tab: Hashable, CaseIterable {
        case financial
        case assets

        var titleKey: LocalizedStringKey {
            switch self {
            case .financial: return "overview.tab.financial"
            case .assets: return "overview.tab.assets"
            }
        }

        var iconName: String {
            switch self {
            case .financial: return "chart.line.uptrend.xyaxis"
            case .assets: return "house.and.flag"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]
    @Query(sort: \PortfolioSnapshot.periodMonth, order: .reverse)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @State private var isUpdating: Bool = false
    @State private var selectedYear: Int? = nil
    @State private var selectedTab: Tab = .financial

    /// One-shot derivation for the financial tab. Computed in a single
    /// pass per `body` render so the hero, members, and snapshot cards
    /// share one holdings fetch + FX cache + sorted-snapshot index.
    private struct FinancialDerivation {
        var totals: NetWorthCalculator.Totals
        var memberTotals: [NetWorthCalculator.MemberTotal]
        /// Month-over-month percentage delta for the household total.
        var monthDeltaPercent: Double?
        /// Month-over-month absolute delta in `homeCurrency`.
        var monthDeltaAmount: Decimal?
        /// Per-member month-over-month percentage deltas, keyed by id.
        var memberDeltaPercent: [UUID: Double]
        /// Last six months of net worth — used for the hero sparkline.
        var sparkline: [OverviewSparkline.Point]
    }

    private func deriveFinancial() -> FinancialDerivation {
        _ = snapshots.count + rates.count + holdings.count + members.count
        let bundle = NetWorthCalculator.bundle(
            homeCurrency: homeCurrency,
            includeMemberBreakdown: true,
            context: context
        )

        // Prior month — computed once, reused for absolute delta + per-member.
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let thisMonth = Snapshot.normalize(.now)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth)

        var deltaAmount: Decimal?
        var memberDeltas: [UUID: Double] = [:]

        if let lastMonth {
            let prevTotal = NetWorthCalculator.total(
                homeCurrency: homeCurrency,
                asOf: lastMonth,
                context: context
            )
            deltaAmount = bundle.totals.amount - prevTotal.amount

            let prevMembers = NetWorthCalculator.totalsByMember(
                homeCurrency: homeCurrency,
                asOf: lastMonth,
                context: context
            )
            let prevById = Dictionary(uniqueKeysWithValues: prevMembers.map { ($0.memberId, $0.amount) })
            for entry in bundle.byMember {
                guard let prior = prevById[entry.memberId], prior != 0 else { continue }
                let change = (entry.amount - prior) / prior
                memberDeltas[entry.memberId] = NSDecimalNumber(decimal: change).doubleValue
            }
        }

        let trend = NetWorthCalculator.trend(
            homeCurrency: homeCurrency,
            months: 6,
            context: context
        )
        let sparkline = trend.map {
            OverviewSparkline.Point(
                period: $0.period,
                amount: NSDecimalNumber(decimal: $0.amount).doubleValue
            )
        }

        return FinancialDerivation(
            totals: bundle.totals,
            memberTotals: bundle.byMember,
            monthDeltaPercent: bundle.monthOverMonthDelta,
            monthDeltaAmount: deltaAmount,
            memberDeltaPercent: memberDeltas,
            sparkline: sparkline
        )
    }

    var body: some View {
        Group {
            #if os(iOS)
            iosBody
            #else
            macBody
            #endif
        }
        .ambientBackground()
        .navigationTitle("overview.title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            // Plain "+" style action in the nav bar on iOS, matching
            // the Accounts screen.
            ToolbarItem(placement: .primaryAction) {
                if selectedTab == .financial && !holdings.isEmpty {
                    Button {
                        isUpdating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("overview.addSnapshot"))
                }
            }
            #endif
        }
        .sheet(isPresented: $isUpdating) {
            BatchEntryView()
        }
        .onAppear {
            if selectedYear == nil, let latest = availableYears.first {
                selectedYear = latest
            }
        }
        .onChange(of: availableYears) { _, newYears in
            if let selected = selectedYear, !newYears.contains(selected) {
                selectedYear = newYears.first
            } else if selectedYear == nil {
                selectedYear = newYears.first
            }
        }
    }

    #if os(macOS)
    /// macOS body: native segmented `Picker` above a single ScrollView that
    /// swaps between the financial and assets tabs. Matches the iOS shape
    /// for consistency; horizontal swipe-to-switch is iOS only because
    /// paged `TabView` is unavailable on macOS.
    private var macBody: some View {
        VStack(spacing: 0) {
            tabPicker
                .frame(maxWidth: 420)
                .pageHorizontalPadding()
                .padding(.top, 12)
                .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .financial:
                        financialTab
                    case .assets:
                        AssetsView()
                    }
                }
                .pageHorizontalPadding()
                .padding(.vertical, 20)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            // Avoid right-edge jitter: when the system scrollbar style is
            // "Always show", the vertical scroller toggles as content height
            // crosses the viewport, shifting card right-edges by ~15pt.
            // Hiding the indicator keeps layout stable; trackpad scroll and
            // keyboard navigation still work.
            .scrollIndicators(.hidden)
        }
    }
    #endif

    #if os(iOS)
    /// iOS body uses a native segmented `Picker` (cheap to render, no
    /// custom gradients/backdrops) and a paged `TabView` so the user can
    /// swipe horizontally between Financial and Assets. This replaces a
    /// custom glass segmented control that was janky on iOS.
    private var iosBody: some View {
        VStack(spacing: 0) {
            tabPicker
                .pageHorizontalPadding()
                .padding(.top, 8)
                .padding(.bottom, 4)

            TabView(selection: $selectedTab) {
                ScrollView {
                    VStack(spacing: 20) {
                        financialTab
                    }
                    .pageHorizontalPadding()
                    .padding(.vertical, 20)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .tag(Tab.financial)

                ScrollView {
                    VStack(spacing: 20) {
                        AssetsView()
                    }
                    .pageHorizontalPadding()
                    .padding(.vertical, 20)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .tag(Tab.assets)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
    }
    #endif

    /// Shared segmented picker used by both platforms.
    private var tabPicker: some View {
        Picker("overview.tab.title", selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Text(tab.titleKey).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Financial (holdings-based) tab

    @ViewBuilder
    private var financialTab: some View {
        if holdings.isEmpty {
            ContentUnavailableView(
                "overview.empty.title",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("overview.empty.hint")
            )
            .padding(.top, 64)
        } else {
            let derivation = deriveFinancial()
            VStack(spacing: 20) {
                heroCard(derivation: derivation)
                trendCard
                if !derivation.memberTotals.isEmpty {
                    membersCard(derivation: derivation)
                }
                snapshotsCard
            }
        }
    }

    // MARK: - Cards

    private func heroCard(derivation: FinancialDerivation) -> some View {
        #if os(macOS)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                heroTextBlock(derivation: derivation)
                Spacer()
                addSnapshotButton
            }
            VStack(alignment: .leading, spacing: 16) {
                heroTextBlock(derivation: derivation)
                addSnapshotButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
        #else
        // On iOS the "Add snapshot" action lives in a floating action
        // button overlaid on the ScrollView, so the hero only carries
        // the total and the contextual badges.
        heroTextBlock(derivation: derivation)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        #endif
    }

    private func heroTextBlock(derivation: FinancialDerivation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Eyebrow row — net worth label + tiny home currency tag.
            HStack(spacing: 6) {
                Text("overview.netWorth")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: homeCurrency)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(
                derivation.totals.amount,
                format: .currency(code: homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Color.notionInk)

            // Delta line — the "decision dashboard" headline number.
            if derivation.monthDeltaPercent != nil {
                DeltaBadge(
                    percent: derivation.monthDeltaPercent,
                    amount: derivation.monthDeltaAmount,
                    currencyCode: homeCurrency,
                    locale: locale,
                    style: .full
                )
            }

            // Sparkline — silent trend indicator.
            if derivation.sparkline.count >= 2 {
                OverviewSparkline(
                    points: derivation.sparkline,
                    isPositive: derivation.monthDeltaPercent.map { $0 >= 0 }
                )
                .padding(.top, 2)
            }

            // Subtle context: missing-rates warning OR (de-emphasized)
            // "Rates as of …" footnote.
            if !derivation.totals.missingCurrencies.isEmpty {
                Label {
                    Text(missingRatesMessage(derivation.totals.missingCurrencies))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                .font(.footnote)
                .padding(.top, 4)
            } else if let latest = rates.map(\.date).max() {
                Text(latestRatesFootnote(date: latest))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var addSnapshotButton: some View {
        Button {
            isUpdating = true
        } label: {
            Label {
                Text("overview.addSnapshot")
            } icon: {
                Image(systemName: "square.and.pencil")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var trendCard: some View {
        TrendChartView()
            .glassCard()
    }

    private func membersCard(derivation: FinancialDerivation) -> some View {
        let memberTotals = derivation.memberTotals
        let membersById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let totalAmount = derivation.totals.amount
        let totalDouble = NSDecimalNumber(decimal: totalAmount).doubleValue
        return VStack(alignment: .leading, spacing: 8) {
            Text("overview.byMember")
                .font(.headline)
                .foregroundStyle(Color.notionInk)
                .padding(.bottom, 2)
            VStack(spacing: 0) {
                ForEach(Array(memberTotals.enumerated()), id: \.element.id) { index, entry in
                    let share: Double = {
                        guard totalDouble > 0 else { return 0 }
                        let value = NSDecimalNumber(decimal: entry.amount).doubleValue
                        return max(0, min(1, value / totalDouble))
                    }()
                    OverviewMemberRow(
                        memberId: entry.memberId,
                        memberName: entry.memberName,
                        avatarData: membersById[entry.memberId]?.avatarData,
                        amount: entry.amount,
                        share: share,
                        monthDelta: derivation.memberDeltaPercent[entry.memberId],
                        currencyCode: homeCurrency,
                        locale: locale
                    )
                    if index < memberTotals.count - 1 {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var snapshotsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("overview.snapshots")
                    .font(.headline)
                Spacer()
                if !availableYears.isEmpty {
                    Menu {
                        Button {
                            selectedYear = nil
                        } label: {
                            if selectedYear == nil {
                                Label("overview.snapshots.filter.allYears", systemImage: "checkmark")
                            } else {
                                Text("overview.snapshots.filter.allYears")
                            }
                        }
                        Divider()
                        ForEach(availableYears, id: \.self) { year in
                            Button {
                                selectedYear = year
                            } label: {
                                if selectedYear == year {
                                    Label(String(year), systemImage: "checkmark")
                                } else {
                                    Text(verbatim: String(year))
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text(verbatim: selectedYear.map(String.init) ?? String(localized: "overview.snapshots.filter.allYears"))
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(.callout)
                }
            }
            if portfolioSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("overview.snapshots.empty.title")
                        .font(.callout.weight(.medium))
                    Text("overview.snapshots.empty.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if filteredSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("overview.snapshots.filter.empty")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                        let previous = previousSnapshot(for: snapshot)
                        let isLast = index == filteredSnapshots.count - 1
                        NavigationLink {
                            PortfolioSnapshotDetailView(snapshot: snapshot, previous: previous)
                        } label: {
                            OverviewSnapshotRow(
                                snapshot: snapshot,
                                previous: previous,
                                isLast: isLast,
                                homeCurrency: homeCurrency,
                                locale: locale
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func previousSnapshot(for snapshot: PortfolioSnapshot) -> PortfolioSnapshot? {
        portfolioSnapshots.first {
            $0.homeCurrency == snapshot.homeCurrency &&
            $0.periodMonth < snapshot.periodMonth
        }
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let years = Set(portfolioSnapshots.map { calendar.component(.year, from: $0.periodMonth) })
        return years.sorted(by: >)
    }

    private var filteredSnapshots: [PortfolioSnapshot] {
        guard let selectedYear else { return portfolioSnapshots }
        let calendar = Calendar.current
        return portfolioSnapshots.filter {
            calendar.component(.year, from: $0.periodMonth) == selectedYear
        }
    }

    private func missingRatesMessage(_ currencies: [String]) -> String {
        let list = currencies.joined(separator: ", ")
        let template = String(localized: "overview.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }

    private func latestRatesFootnote(date: Date) -> String {
        let template = String(localized: "overview.ratesAsOf")
        let formatted = date.formatted(.dateTime.year().month().day().locale(locale))
        return template.replacingOccurrences(of: "{date}", with: formatted)
    }

    // MARK: - Actions
}

#if DEBUG
#Preview("Overview · seeded") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        OverviewView()
    }
    .modelContainer(PreviewSampleData.container())
}

#Preview("Overview · empty") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        OverviewView()
    }
    .modelContainer(PreviewSampleData.emptyContainer())
}
#endif

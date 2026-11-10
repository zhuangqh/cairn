import SwiftUI
import SwiftData

/// Net worth hero, snapshots history, and per-member breakdown for the
/// Financial tab. Complements the Dashboard (which emphasizes allocation
/// + activity).
///
/// Hosts a segmented tab at the top so the user can flip between the
/// financial view and a dedicated "Possessions" tab that manages physical
/// possessions (PRD §4.7, v1.1).
struct AssetsView: View {
    enum Tab: Hashable, CaseIterable {
        case financial
        case possessions

        var titleKey: LocalizedStringKey {
            switch self {
            case .financial: return "assets.tab.financial"
            case .possessions: return "assets.tab.possessions"
            }
        }

        var iconName: String {
            switch self {
            case .financial: return "chart.line.uptrend.xyaxis"
            case .possessions: return "house.and.flag"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization

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
    @State private var possessionAddRequest: Int = 0
    @State private var isInspectingPossession = false

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
        var currencyTotals: [NetWorthCalculator.CurrencyTotal]
        /// Per-currency month-over-month percentage deltas, keyed by code.
        var currencyDeltaPercent: [String: Double]
        /// The source snapshot when the displayed values are captured history.
        var sourceSnapshot: PortfolioSnapshot?
    }

    private func deriveFinancial() -> FinancialDerivation {
        _ = snapshots.count + rates.count + holdings.count + members.count
        if let latest = portfolioSnapshots.first(where: { $0.homeCurrency == homeCurrency }) {
            return deriveFinancial(from: latest)
        }

        // Before the first portfolio snapshot exists, retain the live
        // calculation so the empty state still gives the user a useful total.
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
        var currencyDeltas: [String: Double] = [:]

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

            currencyDeltas = Self.currencyDeltas(
                current: bundle.byCurrency,
                previous: NetWorthCalculator.totalsByCurrency(
                    homeCurrency: homeCurrency,
                    asOf: lastMonth,
                    context: context
                )
            )
        }

        return FinancialDerivation(
            totals: bundle.totals,
            memberTotals: bundle.byMember,
            monthDeltaPercent: bundle.monthOverMonthDelta,
            monthDeltaAmount: deltaAmount,
            memberDeltaPercent: memberDeltas,
            currencyTotals: bundle.byCurrency,
            currencyDeltaPercent: currencyDeltas,
            sourceSnapshot: nil
        )
    }

    /// Once history exists, the Assets summary is a view of the latest
    /// captured portfolio snapshot. This keeps the headline, member totals,
    /// and deltas on the same frozen balances and FX rates.
    private func deriveFinancial(from latest: PortfolioSnapshot) -> FinancialDerivation {
        let previous = previousSnapshot(for: latest)
        let latestMembers = memberTotals(in: latest)
        let previousById = Dictionary(
            uniqueKeysWithValues: previous.map(memberTotals(in:))?.map { ($0.memberId, $0.amount) } ?? []
        )

        let deltaAmount = previous.map { latest.totalAmount - $0.totalAmount }
        let deltaPercent: Double? = previous.flatMap { prior in
            guard prior.totalAmount != 0 else { return nil }
            let change = (latest.totalAmount - prior.totalAmount) / prior.totalAmount
            return NSDecimalNumber(decimal: change).doubleValue
        }

        var memberDeltas: [UUID: Double] = [:]
        for entry in latestMembers {
            guard let prior = previousById[entry.memberId], prior != 0 else { continue }
            let change = (entry.amount - prior) / prior
            memberDeltas[entry.memberId] = NSDecimalNumber(decimal: change).doubleValue
        }

        let latestCurrencies = NetWorthCalculator.currencyTotals(in: latest.entries)
        return FinancialDerivation(
            totals: .init(amount: latest.totalAmount, missingCurrencies: []),
            memberTotals: latestMembers,
            monthDeltaPercent: deltaPercent,
            monthDeltaAmount: deltaAmount,
            memberDeltaPercent: memberDeltas,
            currencyTotals: latestCurrencies,
            currencyDeltaPercent: Self.currencyDeltas(
                current: latestCurrencies,
                previous: previous.map { NetWorthCalculator.currencyTotals(in: $0.entries) } ?? []
            ),
            sourceSnapshot: latest
        )
    }

    /// Converted-amount change per currency; skipped when either side lacks
    /// a rate or the prior balance is zero.
    private static func currencyDeltas(
        current: [NetWorthCalculator.CurrencyTotal],
        previous: [NetWorthCalculator.CurrencyTotal]
    ) -> [String: Double] {
        let priorByCode = Dictionary(uniqueKeysWithValues: previous.map { ($0.currency, $0.convertedAmount) })
        var deltas: [String: Double] = [:]
        for entry in current {
            guard let value = entry.convertedAmount,
                  let prior = priorByCode[entry.currency] ?? nil,
                  prior != 0 else { continue }
            deltas[entry.currency] = NSDecimalNumber(decimal: (value - prior) / prior).doubleValue
        }
        return deltas
    }

    private func memberTotals(in snapshot: PortfolioSnapshot) -> [NetWorthCalculator.MemberTotal] {
        let holdingsById = Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0) })
        var amountsByMemberId: [UUID: Decimal] = [:]

        for entry in snapshot.entries {
            guard let amount = entry.convertedAmount else { continue }
            let resolvedMember = entry.holdingId
                .flatMap { holdingsById[$0]?.account?.member }
                ?? members.first(where: { $0.name == entry.memberName })
            guard let resolvedMember else { continue }
            amountsByMemberId[resolvedMember.id, default: 0] += amount
        }

        return members.compactMap { member in
            guard let amount = amountsByMemberId[member.id] else { return nil }
            return NetWorthCalculator.MemberTotal(
                memberId: member.id,
                memberName: member.name,
                amount: amount
            )
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            iosBody
            #else
            macBody
            #endif
        }
        .possessionInspectionHost(isPresented: $isInspectingPossession)
        .ambientBackground()
        .navigationTitle(Text("assets.title", bundle: localization.bundle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            // Plain "+" style action in the nav bar on iOS, matching
            // the Accounts screen.
            ToolbarItem(placement: .primaryAction) {
                // Hidden while a showcase item is open; the overlay owns the screen.
                if canAddInSelectedTab, !isInspectingPossession {
                    Button {
                        performPrimaryAddAction()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(primaryAddLabel)
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
    /// swaps between the financial and possessions tabs. Matches the iOS shape
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
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .financial:
                        financialTab
                    case .possessions:
                        PossessionsView(addRequest: possessionAddRequest)
                    }
                }
                .pageHorizontalPadding()
                .padding(.bottom, 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            // Avoid right-edge jitter: when the system scrollbar style is
            // "Always show", the vertical scroller toggles as content height
            // crosses the viewport, shifting card right-edges by ~15pt.
            // Hiding the indicator keeps layout stable while preserving
            // standard scroll input.
            .scrollIndicators(.hidden)
        }
    }
    #endif

    #if os(iOS)
    /// Keep the vertical scroll view directly visible to the app-level
    /// `TabView` so iOS can minimize the bottom tab bar while scrolling.
    /// A direction-locked gesture preserves horizontal tab switching without
    /// introducing a nested paging scroll view.
    private var iosBody: some View {
        VStack(spacing: 0) {
            tabPicker
                .pageHorizontalPadding()
                .padding(.top, 6)
                .padding(.bottom, 2)

            ScrollView {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .financial:
                        financialTab
                    case .possessions:
                        PossessionsView(addRequest: possessionAddRequest)
                    }
                }
                .pageHorizontalPadding()
                .padding(.bottom, 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(horizontalTabSwipe)
        }
    }

    private var horizontalTabSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                guard abs(horizontal) > 64,
                      abs(horizontal) > abs(vertical) * 1.4 else { return }

                if horizontal < 0, selectedTab == .financial {
                    selectedTab = .possessions
                } else if horizontal > 0, selectedTab == .possessions {
                    selectedTab = .financial
                }
            }
    }
    #endif

    /// Page-level segmented control (design.md §5.7).
    private var tabPicker: some View {
        LedgerSegmentedControl(selection: $selectedTab, options: Tab.allCases) { tab in
            Text(tab.titleKey)
        }
        .frame(maxWidth: 420)
    }

    private var canAddInSelectedTab: Bool {
        switch selectedTab {
        case .financial:
            return !holdings.isEmpty
        case .possessions:
            return !members.isEmpty
        }
    }

    private var primaryAddLabel: Text {
        switch selectedTab {
        case .financial:
            Text("assets.addSnapshot")
        case .possessions:
            Text("possession.new.title")
        }
    }

    private func performPrimaryAddAction() {
        switch selectedTab {
        case .financial:
            isUpdating = true
        case .possessions:
            possessionAddRequest += 1
        }
    }

    // MARK: - Financial (holdings-based) tab

    @ViewBuilder
    private var financialTab: some View {
        if holdings.isEmpty {
            ContentUnavailableView(
                "assets.empty.title",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("assets.empty.hint")
            )
            .padding(.top, 64)
        } else {
            let derivation = deriveFinancial()
            VStack(alignment: .leading, spacing: 0) {
                heroCard(derivation: derivation)
                bottomRow(derivation: derivation)
            }
        }
    }

    /// Breakdown cards (by member, then by currency) + snapshots. On wide
    /// macOS windows the breakdowns stack in the leading column beside
    /// snapshots; everywhere else everything stacks vertically.
    @ViewBuilder
    private func bottomRow(derivation: FinancialDerivation) -> some View {
        let hasMembers = !derivation.memberTotals.isEmpty
        // A single currency would be one 100% row, so the card waits for two.
        let hasCurrencies = derivation.currencyTotals.count > 1
        #if os(macOS)
        if hasMembers || hasCurrencies {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 40) {
                    VStack(spacing: 0) {
                        if hasMembers { membersCard(derivation: derivation) }
                        if hasCurrencies { currencyCard(derivation: derivation) }
                    }
                    .frame(minWidth: 380, maxWidth: .infinity)
                    snapshotsCard
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
                VStack(spacing: 0) {
                    if hasMembers { membersCard(derivation: derivation) }
                    if hasCurrencies { currencyCard(derivation: derivation) }
                    snapshotsCard
                }
            }
        } else {
            snapshotsCard
        }
        #else
        VStack(spacing: 0) {
            if hasMembers { membersCard(derivation: derivation) }
            if hasCurrencies { currencyCard(derivation: derivation) }
            snapshotsCard
        }
        #endif
    }

    // MARK: - Cards

    /// Hero summary (§5.2) for the latest snapshot. On macOS the "Add
    /// snapshot" action sits under it; on iOS it lives in the navigation bar.
    @ViewBuilder
    private func heroCard(derivation: FinancialDerivation) -> some View {
        LedgerHero(
            eyebrow: Text("assets.netWorth"),
            amount: derivation.totals.amount,
            code: homeCurrency,
            locale: locale,
            deltaAmount: derivation.monthDeltaPercent == nil ? nil : derivation.monthDeltaAmount,
            deltaPercent: derivation.monthDeltaPercent
        ) {
            heroMeta(derivation: derivation)
        }
        #if os(macOS)
        addSnapshotButton
            .padding(.bottom, 20)
        #endif
    }

    /// Snapshot month, or a missing-rates warning / rates footnote for the
    /// live (pre-snapshot) total.
    @ViewBuilder
    private func heroMeta(derivation: FinancialDerivation) -> some View {
        if !derivation.totals.missingCurrencies.isEmpty {
            Label {
                Text(missingRatesMessage(derivation.totals.missingCurrencies))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Color.red)
        } else if let snapshot = derivation.sourceSnapshot {
            Text(snapshot.periodMonth, format: .dateTime.year().month(.wide).locale(locale))
        } else if let latest = rates.map(\.date).max() {
            Text(latestRatesFootnote(date: latest))
        }
    }

    private var addSnapshotButton: some View {
        Button {
            isUpdating = true
        } label: {
            Label {
                Text("assets.addSnapshot")
            } icon: {
                Image(systemName: "square.and.pencil")
            }
        }
        .controlSize(.large)
        .cairnProminentButtonStyle()
    }

    private func membersCard(derivation: FinancialDerivation) -> some View {
        let memberTotals = derivation.memberTotals
        let membersById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let totalAmount = derivation.totals.amount
        let totalDouble = NSDecimalNumber(decimal: totalAmount).doubleValue
        return AssetsBreakdownCard(titleKey: "assets.byMember") {
            ForEach(memberTotals) { entry in
                let share: Double = {
                    guard totalDouble > 0 else { return 0 }
                    let value = NSDecimalNumber(decimal: entry.amount).doubleValue
                    return max(0, min(1, value / totalDouble))
                }()
                AssetsMemberRow(
                    memberId: entry.memberId,
                    memberName: entry.memberName,
                    avatarData: membersById[entry.memberId]?.avatarData,
                    accountCount: membersById[entry.memberId].map { member in
                        (member.accounts ?? []).filter { !$0.isArchived }.count
                    },
                    amount: entry.amount,
                    share: share,
                    monthDelta: derivation.memberDeltaPercent[entry.memberId],
                    currencyCode: homeCurrency,
                    locale: locale
                )
            }
        }
    }

    private func currencyCard(derivation: FinancialDerivation) -> some View {
        AssetsCurrencyCard(
            totals: derivation.currencyTotals,
            householdTotal: derivation.totals.amount,
            monthDeltas: derivation.currencyDeltaPercent,
            homeCurrency: homeCurrency,
            locale: locale
        )
    }

    private var snapshotsCard: some View {
        LedgerSection(Text("assets.snapshots")) {
            if !availableYears.isEmpty {
                yearFilterMenu
            }
        } content: {
            if portfolioSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("assets.snapshots.empty.title")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text("assets.snapshots.empty.hint")
                        .font(.footnote)
                        .foregroundStyle(Color.ink2)
                }
                .padding(.vertical, 8)
            } else if filteredSnapshots.isEmpty {
                Text("assets.snapshots.filter.empty")
                    .font(.callout)
                    .foregroundStyle(Color.ink2)
                    .padding(.vertical, 8)
            } else {
                LedgerRows(data: filteredSnapshots) { snapshot in
                    let previous = previousSnapshot(for: snapshot)
                    NavigationLink {
                        PortfolioSnapshotDetailView(snapshot: snapshot, previous: previous)
                    } label: {
                        AssetsSnapshotRow(
                            snapshot: snapshot,
                            previous: previous,
                            homeCurrency: homeCurrency,
                            locale: locale
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var yearFilterMenu: some View {
        Menu {
            Button {
                selectedYear = nil
            } label: {
                if selectedYear == nil {
                    Label("assets.snapshots.filter.allYears", systemImage: "checkmark")
                } else {
                    Text("assets.snapshots.filter.allYears")
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
            LedgerFilterLabel(
                title: selectedYear.map(String.init) ?? String(localized: "assets.snapshots.filter.allYears")
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
        let template = String(localized: "assets.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }

    private func latestRatesFootnote(date: Date) -> String {
        let template = String(localized: "assets.ratesAsOf")
        let formatted = date.formatted(.dateTime.year().month().day().locale(locale))
        return template.replacingOccurrences(of: "{date}", with: formatted)
    }

    // MARK: - Actions
}

#if DEBUG
#Preview("Assets · seeded") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        AssetsView()
    }
    .environment(LocalizationService())
    .modelContainer(PreviewSampleData.container())
}

#Preview("Assets · empty") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        AssetsView()
    }
    .environment(LocalizationService())
    .modelContainer(PreviewSampleData.emptyContainer())
}
#endif

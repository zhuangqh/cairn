import SwiftUI
import SwiftData

/// Pages the Assets screen pushes. Pushes in the sidebar stacks must be
/// value-based: on macOS a `NavigationLink(destination:)` page lands in the
/// split view's own column and outlives sidebar switches (see `RootView`).
enum AssetsRoute: Hashable {
    case snapshot(PortfolioSnapshot, previous: PortfolioSnapshot?)
}

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
    @State private var selectedYear: Int?
    @State private var selectedTab: Tab = .financial
    @State private var possessionAddRequest: Int = 0
    @State private var isInspectingPossession = false

    /// One-shot derivation for the financial tab. Computed in a single
    /// pass per `body` render so the hero, members, and snapshot cards
    /// share one holdings fetch + FX cache + sorted-snapshot index.
    private func deriveFinancial(listing: SnapshotListing) -> AssetsSummaryService.Summary {
        _ = snapshots.count + rates.count + holdings.count + members.count
        if let latest = portfolioSnapshots.first(where: { $0.homeCurrency == homeCurrency }) {
            return AssetsSummaryService.summary(
                from: latest,
                previous: listing.previous(for: latest),
                members: members,
                holdings: holdings
            )
        }
        return AssetsSummaryService.liveSummary(homeCurrency: homeCurrency, context: context)
    }

    var body: some View {
        let years = availableYears
        return Group {
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
        .navigationDestination(for: AssetsRoute.self) { route in
            switch route {
            case let .snapshot(snapshot, previous):
                PortfolioSnapshotDetailView(snapshot: snapshot, previous: previous)
            }
        }
        .onAppear {
            if selectedYear == nil, let latest = years.first {
                selectedYear = latest
            }
        }
        .onChange(of: years) { _, newYears in
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

    /// Page-level segmented control (DESIGN.md §5.7).
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
            let listing = snapshotListing()
            let derivation = deriveFinancial(listing: listing)
            VStack(alignment: .leading, spacing: 0) {
                heroCard(derivation: derivation)
                bottomRow(derivation: derivation, listing: listing)
            }
        }
    }

    /// Breakdown cards (by member, then by currency) + snapshots. On wide
    /// macOS windows the breakdowns stack in the leading column beside
    /// snapshots; everywhere else everything stacks vertically.
    @ViewBuilder
    private func bottomRow(derivation: AssetsSummaryService.Summary, listing: SnapshotListing) -> some View {
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
                    snapshotsCard(listing)
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
                VStack(spacing: 0) {
                    if hasMembers { membersCard(derivation: derivation) }
                    if hasCurrencies { currencyCard(derivation: derivation) }
                    snapshotsCard(listing)
                }
            }
        } else {
            snapshotsCard(listing)
        }
        #else
        VStack(spacing: 0) {
            if hasMembers { membersCard(derivation: derivation) }
            if hasCurrencies { currencyCard(derivation: derivation) }
            snapshotsCard(listing)
        }
        #endif
    }

    // MARK: - Cards

    /// Hero summary (§5.2) for the latest snapshot. On macOS the "Add
    /// snapshot" action sits under it; on iOS it lives in the navigation bar.
    @ViewBuilder
    private func heroCard(derivation: AssetsSummaryService.Summary) -> some View {
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
    private func heroMeta(derivation: AssetsSummaryService.Summary) -> some View {
        if !derivation.totals.missingCurrencies.isEmpty {
            Label {
                Text(MissingRatesMessage.text(for: derivation.totals.missingCurrencies))
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

    private func membersCard(derivation: AssetsSummaryService.Summary) -> some View {
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

    private func currencyCard(derivation: AssetsSummaryService.Summary) -> some View {
        AssetsCurrencyCard(
            totals: derivation.currencyTotals,
            householdTotal: derivation.totals.amount,
            monthDeltas: derivation.currencyDeltaPercent,
            homeCurrency: homeCurrency,
            locale: locale
        )
    }

    private func snapshotsCard(_ listing: SnapshotListing) -> some View {
        AssetsSnapshotsCard(
            listing: listing,
            hasSnapshots: !portfolioSnapshots.isEmpty,
            selectedYear: $selectedYear,
            homeCurrency: homeCurrency,
            locale: locale
        )
    }

    /// Snapshot history derived once per render: the year filter's options,
    /// the rows it selects, and each row's predecessor.
    struct SnapshotListing {
        let years: [Int]
        let filtered: [PortfolioSnapshot]
        let previousByID: [ObjectIdentifier: PortfolioSnapshot]

        func previous(for snapshot: PortfolioSnapshot) -> PortfolioSnapshot? {
            previousByID[ObjectIdentifier(snapshot)]
        }
    }

    private func snapshotListing() -> SnapshotListing {
        SnapshotListing(
            years: availableYears,
            filtered: filteredSnapshots,
            previousByID: Self.previousSnapshots(in: portfolioSnapshots)
        )
    }

    /// Maps each snapshot to the first entry after it in `descending` (sorted
    /// newest month first) with the same home currency and an earlier month —
    /// a single pass instead of a scan per row. Equal months share their
    /// predecessor, matching the earlier first-match search.
    static func previousSnapshots(
        in descending: [PortfolioSnapshot]
    ) -> [ObjectIdentifier: PortfolioSnapshot] {
        var result: [ObjectIdentifier: PortfolioSnapshot] = [:]
        result.reserveCapacity(descending.count)
        // Walk oldest → newest, remembering per currency the most recently
        // visited snapshot and the predecessor it resolved to.
        var lastByCurrency: [String: (snapshot: PortfolioSnapshot, previous: PortfolioSnapshot?)] = [:]
        for snapshot in descending.reversed() {
            let previous: PortfolioSnapshot?
            if let last = lastByCurrency[snapshot.homeCurrency] {
                previous = last.snapshot.periodMonth < snapshot.periodMonth ? last.snapshot : last.previous
            } else {
                previous = nil
            }
            if let previous { result[ObjectIdentifier(snapshot)] = previous }
            lastByCurrency[snapshot.homeCurrency] = (snapshot, previous)
        }
        return result
    }

    private var availableYears: [Int] {
        LedgerYearFilterMenu.years(of: portfolioSnapshots.lazy.map(\.periodMonth))
    }

    private var filteredSnapshots: [PortfolioSnapshot] {
        LedgerYearFilterMenu.filter(portfolioSnapshots, year: selectedYear, date: \.periodMonth)
    }

    private func latestRatesFootnote(date: Date) -> String {
        let template = String(localized: "assets.ratesAsOf")
        let formatted = date.formatted(.dateTime.year().month().day().locale(locale))
        return template.replacingOccurrences(of: "{date}", with: formatted)
    }
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

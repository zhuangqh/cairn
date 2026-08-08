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

        return FinancialDerivation(
            totals: bundle.totals,
            memberTotals: bundle.byMember,
            monthDeltaPercent: bundle.monthOverMonthDelta,
            monthDeltaAmount: deltaAmount,
            memberDeltaPercent: memberDeltas
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
        .navigationTitle(Text("assets.title", bundle: localization.bundle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            // Plain "+" style action in the nav bar on iOS, matching
            // the Accounts screen.
            ToolbarItem(placement: .primaryAction) {
                if canAddInSelectedTab {
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
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .financial:
                        financialTab
                    case .possessions:
                        PossessionsView(addRequest: possessionAddRequest)
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
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .financial:
                        financialTab
                    case .possessions:
                        PossessionsView(addRequest: possessionAddRequest)
                    }
                }
                .pageHorizontalPadding()
                .padding(.vertical, 20)
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

    /// Native segmented picker used by both platforms. On iOS 26 and
    /// macOS 26 the system supplies the current Liquid Glass treatment.
    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Label(tab.titleKey, systemImage: tab.iconName)
                    .labelStyle(.titleAndIcon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
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
            VStack(spacing: 20) {
                heroCard(derivation: derivation)
                bottomRow(derivation: derivation)
            }
        }
    }

    /// Snapshots + by-member cards. On wide macOS windows they sit
    /// side-by-side; everywhere else they stack vertically.
    @ViewBuilder
    private func bottomRow(derivation: FinancialDerivation) -> some View {
        let hasMembers = !derivation.memberTotals.isEmpty
        #if os(macOS)
        if hasMembers {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    membersCard(derivation: derivation)
                        .frame(minWidth: 380, maxWidth: .infinity)
                    snapshotsCard
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
                VStack(spacing: 20) {
                    membersCard(derivation: derivation)
                    snapshotsCard
                }
            }
        } else {
            snapshotsCard
        }
        #else
        VStack(spacing: 20) {
            if hasMembers { membersCard(derivation: derivation) }
            snapshotsCard
        }
        #endif
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
                Text("assets.netWorth")
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
        return VStack(alignment: .leading, spacing: 8) {
            Text("assets.byMember")
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
                    AssetsMemberRow(
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
                Text("assets.snapshots")
                    .font(.headline)
                Spacer()
                if !availableYears.isEmpty {
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
                        Label {
                            Text(verbatim: selectedYear.map(String.init) ?? String(localized: "assets.snapshots.filter.allYears"))
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
                    Text("assets.snapshots.empty.title")
                        .font(.callout.weight(.medium))
                    Text("assets.snapshots.empty.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if filteredSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("assets.snapshots.filter.empty")
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
                            AssetsSnapshotRow(
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

import SwiftUI
import SwiftData

/// Home screen of the app, laid out as a 「私人银行」 statement
/// (docs/design.md): sections on the ivory ground separated by hairlines.
///
/// Sections (top → bottom):
///   1. **Hero** — household total, month-over-month change, month.
///   2. **Trend** — combined net-worth curve with its range picker; hovering
///      or dragging time-travels the other sections to that month.
///   3. **Composition** — financial / physical bar plus per-category rows.
///   4. **Members** — one-line row of member shortcuts.
///   5. **Journal** — latest achievement entry.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    // Query sentinels — touch .count in computed vars so @Query invalidates totals.
    @Query private var holdings: [Holding]
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]
    @Query private var members: [Member]
    @Query private var possessions: [Possession]
    @Query private var achievementEvents: [AchievementEvent]

    /// Current hover selection from the embedded trend chart. When set, the
    /// hero / composition / allocation cards render values as of that month.
    @State private var hoverSelection: TrendSelection?
    @State private var isUpdatingMonth = false
    @State private var hasRecomputedAchievements = false

    // MARK: - Derivation

    private var orderedAchievementEvents: [AchievementEvent] {
        achievementEvents.sorted {
            if $0.logicalMonth == $1.logicalMonth { return $0.unlockedAt > $1.unlockedAt }
            return $0.logicalMonth > $1.logicalMonth
        }
    }

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
        _ = holdings.count + snapshots.count + rates.count + members.count + possessions.count

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
        let physical = PossessionService.bundle(
            homeCurrency: homeCurrency,
            asOf: hoverSelection?.period,
            rateCache: rateCache,
            context: context
        )
        let physicalPrev = PossessionService.bundle(
            homeCurrency: homeCurrency,
            asOf: prevAsOf,
            rateCache: rateCache,
            context: context
        )

        let mergedMissing = Set(financial.totals.missingCurrencies)
            .union(physical.totals.missingCurrencies)
            .sorted()

        let byKind = mergeByKind(financial: financial.byKind, physical: physical.byCategory)

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
            missingCurrencies: mergedMissing
        )
    }

    /// Folds physical-possession categories into the per-kind buckets:
    ///   `realEstate / vehicle      → AccountKind.realEstate`
    ///   `electronics / other       → AccountKind.device`
    private func mergeByKind(
        financial: [NetWorthCalculator.KindTotal],
        physical: [PossessionService.CategoryTotal]
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
    /// at `wide` and up the trend + allocation cards share a single row
    /// (macOS only — iPhone keeps everything stacked for readability).
    private enum Layout {
        static let compact: CGFloat = 560
        static let wide: CGFloat = 930
    }

    var body: some View {
        let derivation = derive()
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < Layout.compact
            #if os(macOS)
            let isWide = width >= Layout.wide
            #else
            let isWide = false
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection(derivation: derivation)
                    if isWide {
                        HStack(alignment: .top, spacing: 40) {
                            trendSection
                                .frame(maxWidth: .infinity)
                            compositionSection(derivation: derivation)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        trendSection
                        compositionSection(derivation: derivation)
                    }
                    if !members.isEmpty {
                        membersRow
                    }
                    achievementRow(isCompact: isCompact, financialTotal: derivation.financial)
                }
                .pageHorizontalPadding()
                .padding(.bottom, 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
        }
        .navigationTitle(Text("dashboard.title", bundle: localization.bundle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !holdings.isEmpty {
                    Button {
                        isUpdatingMonth = true
                    } label: {
                        Label("assets.updateThisMonth", systemImage: "calendar.badge.plus")
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
        .sheet(isPresented: $isUpdatingMonth) {
            BatchEntryView()
        }
        .task {
            guard !hasRecomputedAchievements else { return }
            hasRecomputedAchievements = true
            _ = try? AchievementService.recompute(in: context)
        }
        .navigationDestination(for: Member.self) { member in
            MemberDetailView(member: member)
        }
        .navigationDestination(for: Account.self) { account in
            AccountDetailView(account: account)
        }
    }

    // MARK: - Hero

    private func heroSection(derivation: Derivation) -> some View {
        let deltaPercent = Derivation.deltaPercent(
            current: derivation.combined,
            previous: derivation.combinedPrev
        )
        return LedgerHero(
            eyebrow: Text("dashboard.totalWealth"),
            amount: derivation.combined,
            code: homeCurrency,
            locale: locale,
            deltaAmount: deltaPercent == nil ? nil : derivation.combined - derivation.combinedPrev,
            deltaPercent: deltaPercent
        ) {
            Text(effectiveAsOf, format: .dateTime.year().month(.wide).locale(locale))
        }
        .animation(.easeOut(duration: 0.2), value: derivation.combined)
    }

    // MARK: - Trend

    private var trendSection: some View {
        TrendChartView(
            showPossessionOverlay: true,
            onSelectionChange: { selection in
                withAnimation(.easeOut(duration: 0.15)) {
                    hoverSelection = selection
                }
            }
        )
    }

    // MARK: - Composition

    private func compositionSection(derivation: Derivation) -> some View {
        LedgerSection(Text("dashboard.composition")) {
            CompositionBreakdownView(
                financial: derivation.financial,
                physical: derivation.physical,
                entries: derivation.allocation,
                homeCurrency: homeCurrency
            )
        }
    }

    // MARK: - Members

    /// One-line row: label, then each member as avatar + given name. Each
    /// member opens its detail; overflow scrolls horizontally.
    private var membersRow: some View {
        let sorted = members.sorted { $0.createdAt < $1.createdAt }
        return HStack(spacing: 16) {
            Text("dashboard.members")
                .font(.callout)
                .foregroundStyle(Color.ink2)
                .fixedSize()
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                memberChips(sorted)
                ScrollView(.horizontal, showsIndicators: false) {
                    memberChips(sorted)
                }
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { LedgerHairline() }
    }

    private func memberChips(_ sorted: [Member]) -> some View {
        HStack(spacing: 16) {
            ForEach(sorted) { member in
                NavigationLink(value: member) {
                    HStack(spacing: 8) {
                        MemberAvatarView(
                            name: member.name,
                            avatarData: member.avatarData,
                            seed: member.id,
                            size: 28
                        )
                        Text(verbatim: givenName(of: member.name))
                            .font(.callout)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        LedgerChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Display the first whitespace-separated component as the
    /// "given" name. Falls back to the full string when there is no
    /// space (single-token names are common in CJK locales).
    private func givenName(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.split(separator: " ").first {
            return String(first)
        }
        return trimmed
    }

    // MARK: - Achievements

    /// Journal entry row (§5.9): 44pt badge, eyebrow line, then the latest
    /// achievement name with its month. Wider layouts add progress toward the
    /// next wealth milestone.
    private func achievementRow(isCompact: Bool, financialTotal: Decimal) -> some View {
        let latest = orderedAchievementEvents.first.map(AchievementPresentation.init)
        let latestWealthIndex = orderedAchievementEvents
            .filter { $0.family == .wealthMilestone }
            .compactMap { AchievementService.wealthStageIndex(from: $0.stageKey) }
            .max()
        let nextThreshold = AchievementService.wealthThreshold(at: (latestWealthIndex ?? -1) + 1)
        let previousThreshold = latestWealthIndex.map { AchievementService.wealthThreshold(at: $0) } ?? 0
        let progressRange = max(nextThreshold - previousThreshold, 1)
        let progressValue = min(max((financialTotal - previousThreshold) / progressRange, 0), 1)

        return NavigationLink {
            AchievementJournalView()
        } label: {
            HStack(spacing: LedgerMetrics.columnSpacing) {
                AchievementBadgeView(
                    family: latest?.family ?? .prologue,
                    stageKey: latest?.stageKey ?? "first-stone",
                    size: 44
                )
                .saturation(latest == nil ? 0 : 1)
                .opacity(latest == nil ? 0.55 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(latest == nil ? "achievement.dashboard.eyebrow" : "achievement.dashboard.latest",
                         bundle: localization.bundle)
                        .font(.caption)
                        .foregroundStyle(Color.ink2)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(
                            latest.map { LocalizedStringKey($0.titleKey) }
                                ?? LocalizedStringKey("achievement.firstStone.title"),
                            bundle: localization.bundle
                        )
                        .font(.headline)
                        .foregroundStyle(Color.ink)

                        if let latest {
                            Text(verbatim: AchievementFormatting.month(latest.logicalMonth, locale: locale))
                                .font(.footnote)
                                .foregroundStyle(Color.ink3)
                        }
                    }
                    if latest == nil {
                        Text("achievement.dashboard.empty", bundle: localization.bundle)
                            .font(.footnote)
                            .foregroundStyle(Color.ink3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isCompact {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("achievement.dashboard.next", bundle: localization.bundle)
                                .foregroundStyle(Color.ink3)
                            Text(
                                nextThreshold,
                                format: .currency(code: homeCurrency)
                                    .precision(.fractionLength(0))
                                    .locale(locale)
                            )
                            .monospacedDigit()
                            .foregroundStyle(Color.ink)
                        }
                        .font(.footnote)
                        LedgerMeter(progress: NSDecimalNumber(decimal: progressValue).doubleValue)
                            .frame(width: 140)
                        Text("achievement.dashboard.financialOnly", bundle: localization.bundle)
                            .font(.caption2)
                            .foregroundStyle(Color.ink3)
                    }
                }

                LedgerChevron()
            }
            .frame(minHeight: 60)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { LedgerHairline() }
        .accessibilityHint(Text("achievement.dashboard.open", bundle: localization.bundle))
    }
}

#if DEBUG
#Preview("Dashboard · seeded") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        DashboardView()
    }
    .environment(LocalizationService())
    .modelContainer(PreviewSampleData.container())
}

#Preview("Dashboard · empty") {
    PreviewDefaults.primeOnboarded()
    return NavigationStack {
        DashboardView()
    }
    .environment(LocalizationService())
    .modelContainer(PreviewSampleData.emptyContainer())
}
#endif

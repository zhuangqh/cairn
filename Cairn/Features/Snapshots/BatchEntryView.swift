import SwiftUI
import SwiftData

/// Spreadsheet-style monthly snapshot entry (PRD §4.3.5). One row per active
/// Holding, grouped by Member. Only the "this month" column is editable.
struct BatchEntryView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(\.locale) var locale
    @Environment(LocalizationService.self) private var localization

    @AppStorage(AppSettingsKeys.homeCurrency)
    var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query var members: [Member]
    @Query var rates: [FXRate]

    @State var periodMonth: Date = Snapshot.normalizeDay(.now)
    @State var edits: [UUID: Decimal?] = [:]
    @State private var showClearConfirm: Bool = false
    @State private var showDiscardConfirm: Bool = false
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @State private var unlockedAchievements: [AchievementPresentation] = []
    @State private var isShowingAchievementUnlock: Bool = false

    /// Historical FX rates fetched for the currently selected month.
    /// Keyed by quote currency; each value means `1 homeCurrency == rate × quote`.
    /// Lives in view state only — never persisted to the `FXRate` cache,
    /// so month-by-month lookups don't pollute "current" rates.
    @State var historicalRates: [String: Decimal] = [:]
    @State var historicalRatesAsOf: Date?
    @State var isLoadingRates: Bool = false
    @State var ratesFetchError: String?

    /// Free-form notes attached to the monthly `PortfolioSnapshot`.
    @State var note: String = ""
    /// Snapshot of `note` at load time so we can detect note-only edits
    /// and let the user save without touching any amount.
    @State var originalNote: String = ""

    /// Seam for tests. Defaults to the live Frankfurter fetcher.
    var ratesFetcher: any FXRateFetching = FrankfurterFetcher()

    /// When set, the month picker is disabled and FX rates are seeded
    /// from these locked values instead of being fetched live. Used when
    /// editing an existing `PortfolioSnapshot` so the historical record
    /// keeps its captured rates and period.
    var lockedRates: [String: Decimal]?

    /// Captured per-holding amounts to use as the saved baseline when
    /// editing an existing `PortfolioSnapshot`. Per-holding `Snapshot`
    /// rows are stored at the original save day (not the month start),
    /// so we can't re-derive these from `Snapshot` lookups keyed on the
    /// portfolio snapshot's normalized month.
    var lockedBaseline: [UUID: Decimal]?

    /// Optional note seed used when editing a captured `PortfolioSnapshot`.
    /// Passing it in avoids an extra fetch before the sheet finishes
    /// building its first frame.
    var initialNote: String?

    var isMonthLocked: Bool { lockedRates != nil }

    init(
        initialPeriodMonth: Date? = nil,
        lockedRates: [String: Decimal]? = nil,
        lockedBaseline: [UUID: Decimal]? = nil,
        initialNote: String? = nil,
        ratesFetcher: any FXRateFetching = FrankfurterFetcher()
    ) {
        if let initialPeriodMonth {
            _periodMonth = State(initialValue: Snapshot.normalizeDay(initialPeriodMonth))
        }
        if let lockedRates {
            _historicalRates = State(initialValue: lockedRates)
        }
        if let initialNote {
            _note = State(initialValue: initialNote)
            _originalNote = State(initialValue: initialNote)
        }
        self.lockedRates = lockedRates
        self.lockedBaseline = lockedBaseline
        self.initialNote = initialNote
        self.ratesFetcher = ratesFetcher
    }

    var body: some View {
        let pass = derivePass()
        let hasUnsavedEdits = hasUnsavedEdits(rows: pass.rows)
        NavigationStack {
            ZStack {
                AppBackground()
                if pass.groups.isEmpty {
                    ContentUnavailableView(
                        "batch.empty.title",
                        systemImage: "tablecells",
                        description: Text("batch.empty.hint")
                    )
                } else {
                    entryScroll(pass)
                }
            }
            // One task keyed on both inputs: a newer month or currency
            // cancels the in-flight fetch so a stale response never lands.
            .task(id: RatesKey(periodMonth: periodMonth, homeCurrency: homeCurrency)) {
                await loadHistoricalRates()
                guard !Task.isCancelled else { return }
                loadNoteForCurrentMonth()
            }
            .navigationTitle(navTitle)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent(hasUnsavedEdits: hasUnsavedEdits) }
            .keyboardDismissable(showsToolbar: false)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !pass.groups.isEmpty {
                    footer(pass, hasUnsavedEdits: hasUnsavedEdits)
                }
            }
            .alert(
                "batch.clear.confirm.title",
                isPresented: $showClearConfirm
            ) {
                Button(role: .destructive) {
                    clearAll()
                } label: {
                    Text("batch.clear.confirm.action")
                }
                Button(role: .cancel) {} label: { Text("common.action.cancel") }
            } message: {
                Text("batch.clear.confirm.message")
            }
            .alert(
                "batch.discard.confirm.title",
                isPresented: $showDiscardConfirm
            ) {
                Button(role: .destructive) {
                    dismiss()
                } label: {
                    Text("batch.discard.confirm.action")
                }
                Button(role: .cancel) {} label: { Text("common.action.cancel") }
            } message: {
                Text("batch.discard.confirm.message")
            }
            .alert(
                "batch.save.failure",
                isPresented: Binding(isPresent: $errorMessage)
            ) {
                Button { errorMessage = nil } label: { Text("common.action.done") }
            } message: {
                if let errorMessage { Text(verbatim: errorMessage) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
        .sheet(isPresented: $isShowingAchievementUnlock, onDismiss: { dismiss() }) {
            AchievementUnlockView(events: unlockedAchievements) {
                isShowingAchievementUnlock = false
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Header / toolbar

    private var navTitle: String {
        if isMonthLocked {
            let template = String(localized: "batch.title", bundle: localization.bundle)
            let formatted = periodMonth.formatted(.dateTime.year().month(.wide).locale(locale).inUTC)
            return template.replacingOccurrences(of: "{month}", with: formatted)
        } else {
            return String(localized: "batch.title.add", bundle: localization.bundle)
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(hasUnsavedEdits: Bool) -> some ToolbarContent {
        #if !os(macOS)
        ToolbarItem(placement: .cancellationAction) {
            Button {
                if hasUnsavedEdits {
                    showDiscardConfirm = true
                } else {
                    dismiss()
                }
            } label: {
                Text("common.action.cancel")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("batch.save")
                }
            }
            .disabled(!hasUnsavedEdits || isSaving)
            .buttonStyle(.borderedProminent)
        }
        #endif
        #if os(macOS)
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label {
                        Text("batch.clear")
                    } icon: {
                        Image(systemName: "xmark.circle")
                    }
                }
            } label: {
                Label {
                    Text("common.action.more")
                } icon: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        #endif
    }

    // MARK: - Scroll content

    private func entryScroll(_ pass: DerivedPass) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                monthCard(pass.rows)
                memberGroupsSection(pass)
                notesCard
            }
            .padding(.horizontal, pageHorizontalInset)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func memberGroupsSection(_ pass: DerivedPass) -> some View {
        ForEach(pass.groups, id: \.member.id) { group in
            memberGroupCard(group, rateCache: pass.rateCache)
        }
    }

    /// Member group (§4): hairline rule, avatar + name header, then the
    /// member's holdings as entry rows.
    private func memberGroupCard(_ group: MemberGroup, rateCache: FXService.RateCache) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                MemberAvatarView(
                    name: group.member.name,
                    avatarData: group.member.avatarData,
                    seed: group.member.id,
                    size: memberAvatarSize
                )
                Text(verbatim: group.member.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .frame(minHeight: LedgerMetrics.rowHeight)

            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.holding.id) { index, row in
                    entryRow(row, rateCache: rateCache)
                    if index < group.rows.count - 1 {
                        LedgerHairline().padding(.leading, BatchEntryRowView.textColumnInset)
                    }
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { LedgerHairline() }
    }

    private var pageHorizontalInset: CGFloat {
        #if os(macOS)
        24
        #else
        22
        #endif
    }

    private var memberAvatarSize: CGFloat {
        28
    }

    @ViewBuilder
    private func entryRow(_ row: HoldingRow, rateCache: FXService.RateCache) -> some View {
        BatchEntryRowView(
            accountName: row.holding.account?.name ?? "",
            accountKind: row.holding.account?.kind ?? .cash,
            currency: row.holding.currency,
            label: row.holding.label,
            previousAmount: row.previousAmount,
            homeCurrency: homeCurrency,
            convertedPreview: approxHome(for: row, cache: rateCache),
            isDirty: edits[row.holding.id] != nil,
            amount: binding(for: row)
        )
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(_ pass: DerivedPass, hasUnsavedEdits: Bool) -> some View {
        #if os(macOS)
        BatchEntryMacFooter(
            totalInHome: totalInHome(pass),
            homeCurrency: homeCurrency,
            hasUnsavedEdits: hasUnsavedEdits,
            isSaving: isSaving,
            onCancel: {
                if hasUnsavedEdits {
                    showDiscardConfirm = true
                } else {
                    dismiss()
                }
            },
            onSave: save
        )
        #else
        BatchEntryFloatingTotal(
            totalInHome: totalInHome(pass),
            homeCurrency: homeCurrency,
            unresolvedCurrencies: unresolvedCurrencies(pass)
        )
        #endif
    }

    // MARK: - Actions

    private func save() {
        // Per-holding snapshots land on the user's picked day; the
        // `PortfolioSnapshot` is still keyed by month so month-over-month
        // trend points stay stable.
        let day = Snapshot.normalizeDay(periodMonth)
        let isReplacingCapturedSnapshot = lockedBaseline != nil
        let rows: [BatchUpsertService.Row]
        if isReplacingCapturedSnapshot {
            rows = groupedRows
                .flatMap(\.rows)
                .map { row in
                    BatchUpsertService.Row(holdingId: row.holding.id, amount: currentAmount(for: row))
                }
        } else {
            rows = edits.compactMap { key, value in
                guard let value else { return nil }
                return BatchUpsertService.Row(holdingId: key, amount: value)
            }
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await BatchUpsertService.saveBatch(
                    rows,
                    replacingMonth: isReplacingCapturedSnapshot,
                    periodMonth: day,
                    homeCurrency: homeCurrency,
                    note: trimmed.isEmpty ? nil : trimmed,
                    context: context
                )
                let achievementResult = try AchievementService.recompute(in: context)
                edits.removeAll()
                if achievementResult.created.isEmpty {
                    dismiss()
                } else {
                    unlockedAchievements = achievementResult.created
                    isShowingAchievementUnlock = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG
#Preview("BatchEntry · seeded") {
    PreviewDefaults.primeOnboarded()
    return BatchEntryView()
        .modelContainer(PreviewSampleData.container())
        .environment(LocalizationService())
}

#Preview("BatchEntry · empty") {
    PreviewDefaults.primeOnboarded()
    return BatchEntryView()
        .modelContainer(PreviewSampleData.emptyContainer())
        .environment(LocalizationService())
}
#endif

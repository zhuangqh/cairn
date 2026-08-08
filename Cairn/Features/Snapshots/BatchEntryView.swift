import SwiftUI
import SwiftData

/// Spreadsheet-style monthly snapshot entry (PRD §4.3.5). One row per active
/// Holding, grouped by Member. Only the "this month" column is editable.
struct BatchEntryView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(\.locale) var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query var members: [Member]
    @Query var rates: [FXRate]

    @State var periodMonth: Date = Snapshot.normalizeDay(.now)
    @State var edits: [UUID: Decimal?] = [:]
    @State var savedOnce: Set<UUID> = []
    @State private var showClearConfirm: Bool = false
    @State private var showDiscardConfirm: Bool = false
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @State var didPrefill: Bool = false

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
        NavigationStack {
            ZStack {
                AppBackground()
                if groupedRows.isEmpty {
                    ContentUnavailableView(
                        "batch.empty.title",
                        systemImage: "tablecells",
                        description: Text("batch.empty.hint")
                    )
                } else {
                    entryScroll
                        .task { prefillIfNeeded() }
                }
            }
            .task(id: periodMonth) {
                await loadHistoricalRates()
                loadNoteForCurrentMonth()
            }
            .onChange(of: homeCurrency) { _, _ in
                Task { await loadHistoricalRates() }
                loadNoteForCurrentMonth()
            }
            .navigationTitle(navTitle)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .keyboardDismissable(showsToolbar: false)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !groupedRows.isEmpty {
                    footer
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
                isPresented: .init(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button { errorMessage = nil } label: { Text("common.action.done") }
            } message: {
                if let errorMessage { Text(verbatim: errorMessage) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
    }

    // MARK: - Header / toolbar

    private var navTitle: String {
        if isMonthLocked {
            let template = String(localized: "batch.title")
            let formatted = periodMonth.formatted(.dateTime.year().month(.wide).locale(locale))
            return template.replacingOccurrences(of: "{month}", with: formatted)
        } else {
            return String(localized: "batch.title.add")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    private var entryScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                monthCard
                memberGroupsSection
                notesCard
            }
            .pageHorizontalPadding()
            .padding(.vertical, 20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    monthSummary
                    Spacer(minLength: 24)
                    monthControls
                }

                VStack(alignment: .leading, spacing: 14) {
                    monthSummary
                    monthControls
                }
            }

            ratesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 20)
    }

    private var monthSummary: some View {
        HStack(spacing: 12) {
            GlyphBadge(systemName: "calendar", tint: .accentColor, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("batch.monthCard.title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.notionInkSecondary)
                    .textCase(.uppercase)
                    .tracking(0.45)
                Text(verbatim: periodMonth.formatted(.dateTime.year().month(.wide).locale(locale)))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.notionInk)
            }
        }
    }

    private var monthControls: some View {
        HStack(spacing: 10) {
            DatePicker(
                "batch.month",
                selection: $periodMonth,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .disabled(isMonthLocked)
            .onChange(of: periodMonth) { _, newValue in
                let day = Snapshot.normalizeDay(newValue)
                if day != periodMonth { periodMonth = day }
            }

            Button {
                fillFromLast()
            } label: {
                Label("batch.fillFromLast", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(!hasBlankWithPrevious)
            .help(Text("batch.fillFromLast"))
        }
    }

    @ViewBuilder
    private var memberGroupsSection: some View {
        ForEach(groupedRows, id: \.member.id) { group in
            memberGroupCard(group)
        }
    }

    private func memberGroupCard(_ group: MemberGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                MemberAvatarView(
                    name: group.member.name,
                    avatarData: group.member.avatarData,
                    seed: group.member.id,
                    size: 28
                )
                Text(verbatim: group.member.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.notionInk)
                Spacer()
                Text(verbatim: filledSummary(for: group))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Color.notionInkMuted)
            }

            Divider().opacity(0.45)

            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.holding.id) { index, row in
                    entryRow(row)
                    if index < group.rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 20)
    }

    @ViewBuilder
    private func entryRow(_ row: HoldingRow) -> some View {
        BatchEntryRowView(
            accountName: row.holding.account?.name ?? "",
            accountKind: row.holding.account?.kind ?? .cash,
            currency: row.holding.currency,
            label: row.holding.label,
            previousAmount: row.previousAmount,
            homeCurrency: homeCurrency,
            convertedPreview: approxHome(for: row),
            isDirty: edits[row.holding.id] != nil,
            isSaved: savedOnce.contains(row.holding.id),
            amount: binding(for: row)
        )
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        #if os(macOS)
        macFooter
        #else
        iosFloatingTotal
        #endif
    }

    private var footerSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("batch.total")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.notionInkSecondary)
                .textCase(.uppercase)
            Text(totalInHome, format: .currency(code: homeCurrency).locale(locale))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.notionInk)
        }
    }

    private var macFooter: some View {
        HStack(spacing: 16) {
            footerSummary

            Spacer(minLength: 24)

            Button {
                if hasUnsavedEdits {
                    showDiscardConfirm = true
                } else {
                    dismiss()
                }
            } label: {
                Text("common.action.cancel")
            }
            .keyboardShortcut(.cancelAction)

            saveButton
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
        .background(Color.notionSurfaceAlt)
        .overlay(alignment: .top) { Divider().opacity(0.55) }
    }

    private var iosFloatingTotal: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("batch.total")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.notionInkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer(minLength: 8)

                Text(totalInHome, format: .currency(code: homeCurrency).locale(locale))
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.notionInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            if !unresolvedCurrencies.isEmpty {
                Label {
                    Text(unresolvedFootnote)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .liquidGlassBackground(cornerRadius: 16, tint: Color.notionBlue.opacity(0.018))
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 72)
            } else {
                Label("batch.save", systemImage: "checkmark")
            }
        }
        .controlSize(.large)
        .disabled(!hasUnsavedEdits || isSaving)
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Actions

    private func save() {
        // Per-holding snapshots land on the user's picked day; the
        // `PortfolioSnapshot` is still keyed by month so month-over-month
        // trend points stay stable.
        let day = Snapshot.normalizeDay(periodMonth)
        let rows: [BatchUpsertService.Row] = edits.compactMap { key, value in
            guard let value else { return nil }
            return BatchUpsertService.Row(holdingId: key, amount: value)
        }
        let isReplacingCapturedSnapshot = lockedBaseline != nil
        do {
            if isReplacingCapturedSnapshot {
                let replacementRows = groupedRows
                    .flatMap(\.rows)
                    .map { row in
                        BatchUpsertService.Row(
                            holdingId: row.holding.id,
                            amount: currentAmount(for: row)
                        )
                    }
                try BatchUpsertService.replaceMonth(replacementRows, periodMonth: day, context: context)
            } else {
                try BatchUpsertService.apply(rows, periodMonth: day, context: context)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                try await PortfolioSnapshotService.captureForMonth(
                    day,
                    homeCurrency: homeCurrency,
                    note: trimmed.isEmpty ? nil : trimmed,
                    context: context
                )
                savedOnce.formUnion(rows.map(\.holdingId))
                edits.removeAll()
                dismiss()
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
}

#Preview("BatchEntry · empty") {
    PreviewDefaults.primeOnboarded()
    return BatchEntryView()
        .modelContainer(PreviewSampleData.emptyContainer())
}
#endif

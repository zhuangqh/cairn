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
    @State var didPrefillNote: Bool = false
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

    var isMonthLocked: Bool { lockedRates != nil }

    init(
        initialPeriodMonth: Date? = nil,
        lockedRates: [String: Decimal]? = nil,
        lockedBaseline: [UUID: Decimal]? = nil,
        ratesFetcher: any FXRateFetching = FrankfurterFetcher()
    ) {
        if let initialPeriodMonth {
            _periodMonth = State(initialValue: Snapshot.normalizeDay(initialPeriodMonth))
        }
        if let lockedRates {
            _historicalRates = State(initialValue: lockedRates)
        }
        self.lockedRates = lockedRates
        self.lockedBaseline = lockedBaseline
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
            .safeAreaInset(edge: .bottom) {
                if !groupedRows.isEmpty {
                    footer
                }
            }
            .confirmationDialog(
                "batch.clear.confirm.title",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
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
            .confirmationDialog(
                "batch.discard.confirm.title",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
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
        .frame(minWidth: 560, minHeight: 560)
    }

    // MARK: - Header / toolbar

    private var navTitle: String {
        let template = String(localized: "batch.title")
        let formatted = periodMonth.formatted(.dateTime.year().month(.wide).locale(locale))
        return template.replacingOccurrences(of: "{month}", with: formatted)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button {
                    fillFromLast()
                } label: {
                    Label {
                        Text("batch.fillFromLast")
                    } icon: {
                        Image(systemName: "arrow.down.to.line")
                    }
                }
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
    }

    // MARK: - Scroll content

    private var entryScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthCard
                ForEach(groupedRows, id: \.member.id) { group in
                    memberGroupCard(group)
                }
                notesCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                GlyphBadge(systemName: "calendar", tint: .accentColor, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("batch.monthCard.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text(verbatim: periodMonth.formatted(.dateTime.year().month(.wide).locale(locale)))
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                DatePicker(
                    "batch.month",
                    selection: $periodMonth,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .disabled(isMonthLocked)
                .onChange(of: periodMonth) { _, newValue in
                    // Normalize to the start of the picked day (UTC) so the
                    // value stays stable across timezone boundaries without
                    // forcing the user back to the 1st of the month.
                    let day = Snapshot.normalizeDay(newValue)
                    if day != periodMonth { periodMonth = day }
                }
            }

            Divider().opacity(0.4)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("batch.total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalInHome, format: .currency(code: homeCurrency).locale(locale))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("batch.summary.filled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: filledSummary)
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
                Button {
                    fillFromLast()
                } label: {
                    Label {
                        Text("batch.fillFromLast")
                    } icon: {
                        Image(systemName: "arrow.down.to.line")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasBlankWithPrevious)
            }

            ratesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 16)
    }

    private func memberGroupCard(_ group: MemberGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: group.member.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
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
        .glassCard()
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
            amount: binding(for: row.holding.id)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("batch.total")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalInHome, format: .currency(code: homeCurrency).locale(locale))
                    .font(.title3.monospacedDigit().weight(.semibold))
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
        .padding(16)
        .background(Color.notionSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.notionBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Actions

    private func save() {
        // Per-holding snapshots land on the user's picked day; the
        // `PortfolioSnapshot` is still keyed by month so month-over-month
        // trend points stay stable.
        let day = Snapshot.normalizeDay(periodMonth)
        let month = Snapshot.normalize(periodMonth)
        let rows: [BatchUpsertService.Row] = edits.compactMap { key, value in
            guard let value else { return nil }
            return BatchUpsertService.Row(holdingId: key, amount: value)
        }
        do {
            try BatchUpsertService.apply(rows, periodMonth: day, context: context)
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
                    month,
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


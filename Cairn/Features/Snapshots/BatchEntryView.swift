import SwiftUI
import SwiftData

/// Spreadsheet-style monthly snapshot entry (PRD §4.3.5). One row per active
/// Holding, grouped by Member. Only the "this month" column is editable.
/// Supports Fill-from-last, Clear, and atomic Save-all via `BatchUpsertService`.
struct BatchEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query private var members: [Member]
    @Query private var rates: [FXRate]

    @State private var periodMonth: Date = Snapshot.normalize(.now)
    @State private var edits: [UUID: Decimal?] = [:]  // holdingId -> entered value (nil = blank)
    @State private var savedOnce: Set<UUID> = []      // holdings that were saved in this session
    @State private var showClearConfirm: Bool = false
    @State private var showDiscardConfirm: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if groupedRows.isEmpty {
                    ContentUnavailableView(
                        "batch.empty.title",
                        systemImage: "tablecells",
                        description: Text("batch.empty.hint")
                    )
                } else {
                    entryList
                }
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
                Text("batch.save")
            }
            .disabled(!hasUnsavedEdits)
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

    // MARK: - List

    private var entryList: some View {
        List {
            monthSection
            ForEach(groupedRows, id: \.member.id) { group in
                Section {
                    ForEach(group.rows, id: \.holding.id) { row in
                        entryRow(row)
                    }
                } header: {
                    Text(verbatim: group.member.name)
                }
            }
        }
    }

    private var monthSection: some View {
        Section {
            DatePicker(
                "batch.month",
                selection: $periodMonth,
                displayedComponents: [.date]
            )
            .onChange(of: periodMonth) { _, newValue in
                periodMonth = Snapshot.normalize(newValue)
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ row: HoldingRow) -> some View {
        HStack(spacing: 12) {
            statusDot(for: row.holding.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.holding.account?.name ?? "")
                    .font(.body)
                HStack(spacing: 6) {
                    Text(verbatim: row.holding.currency)
                        .font(.caption.monospaced())
                    if let label = row.holding.label, !label.isEmpty {
                        Text(verbatim: label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                TextField(
                    row.lastMonthAmount.map { formatAmount($0) } ?? "",
                    value: binding(for: row.holding.id),
                    format: .number
                )
                .multilineTextAlignment(.trailing)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(minWidth: 100, maxWidth: 140)

                if let approx = approxHome(for: row) {
                    Text(approx, format: .currency(code: homeCurrency).locale(locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if currentAmount(for: row.holding.id) != nil && row.holding.currency != homeCurrency {
                    Text("overview.missingRates.short")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func statusDot(for holdingId: UUID) -> some View {
        let dirty = edits[holdingId] != nil
        let saved = savedOnce.contains(holdingId)
        Circle()
            .fill(dirty ? Color.yellow : (saved ? Color.green : Color.clear))
            .frame(width: 8, height: 8)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("batch.total")
                    .font(.callout)
                Spacer()
                Text(totalInHome, format: .currency(code: homeCurrency).locale(locale))
                    .font(.callout.monospacedDigit())
            }
            if !unresolvedCurrencies.isEmpty {
                Text(unresolvedFootnote)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Derived data

    private struct HoldingRow {
        let holding: Holding
        let lastMonthAmount: Decimal?
    }

    private struct MemberGroup {
        let member: Member
        let rows: [HoldingRow]
    }

    private var groupedRows: [MemberGroup] {
        let calendar = isoCalendar()
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: periodMonth) else {
            return []
        }
        let prevNormalized = Snapshot.normalize(previousMonth)

        return members.compactMap { member in
            let accounts = member.accounts ?? []
            let holdings = accounts
                .flatMap { $0.holdings ?? [] }
                .filter { $0.isArchived == false }
                .sorted { lhs, rhs in
                    let lhsName = lhs.account?.name ?? ""
                    let rhsName = rhs.account?.name ?? ""
                    if lhsName == rhsName { return lhs.currency < rhs.currency }
                    return lhsName < rhsName
                }
            guard !holdings.isEmpty else { return nil }

            let rows = holdings.map { holding in
                HoldingRow(
                    holding: holding,
                    lastMonthAmount: snapshot(for: holding, periodMonth: prevNormalized)?.amount
                )
            }
            return MemberGroup(member: member, rows: rows)
        }
    }

    private func snapshot(for holding: Holding, periodMonth: Date) -> Snapshot? {
        (holding.snapshots ?? []).first { $0.periodMonth == periodMonth }
    }

    private func binding(for holdingId: UUID) -> Binding<Decimal?> {
        Binding(
            get: { edits[holdingId] ?? currentSavedAmount(for: holdingId) },
            set: { newValue in edits[holdingId] = newValue }
        )
    }

    private func currentSavedAmount(for holdingId: UUID) -> Decimal? {
        let rows = groupedRows.flatMap(\.rows)
        guard let holding = rows.first(where: { $0.holding.id == holdingId })?.holding else { return nil }
        return snapshot(for: holding, periodMonth: periodMonth)?.amount
    }

    private func currentAmount(for holdingId: UUID) -> Decimal? {
        if let staged = edits[holdingId] { return staged }
        return currentSavedAmount(for: holdingId)
    }

    private func approxHome(for row: HoldingRow) -> Decimal? {
        guard let amount = currentAmount(for: row.holding.id) else { return nil }
        return FXService.convert(
            amount: amount,
            from: row.holding.currency,
            to: homeCurrency,
            in: context
        )
    }

    private var totalInHome: Decimal {
        groupedRows.flatMap(\.rows).reduce(Decimal(0)) { running, row in
            guard let converted = approxHome(for: row) else { return running }
            return running + converted
        }
    }

    private var unresolvedCurrencies: [String] {
        var codes: Set<String> = []
        for row in groupedRows.flatMap(\.rows) {
            guard let amount = currentAmount(for: row.holding.id), amount != 0 else { continue }
            if row.holding.currency == homeCurrency { continue }
            if FXService.convert(
                amount: amount,
                from: row.holding.currency,
                to: homeCurrency,
                in: context
            ) == nil {
                codes.insert(row.holding.currency)
            }
        }
        return codes.sorted()
    }

    private var unresolvedFootnote: String {
        let template = String(localized: "overview.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: unresolvedCurrencies.joined(separator: ", "))
    }

    private var hasUnsavedEdits: Bool {
        edits.contains { key, value in
            value != currentSavedAmount(for: key)
        }
    }

    // MARK: - Actions

    private func fillFromLast() {
        for row in groupedRows.flatMap(\.rows) {
            // Only fill if this-month input is currently empty/blank.
            let current = currentAmount(for: row.holding.id)
            if current == nil, let last = row.lastMonthAmount {
                edits[row.holding.id] = last
            }
        }
    }

    private func clearAll() {
        for row in groupedRows.flatMap(\.rows) {
            edits[row.holding.id] = Optional<Decimal>.none
        }
    }

    private func save() {
        let normalized = Snapshot.normalize(periodMonth)
        let rows: [BatchUpsertService.Row] = edits.compactMap { key, value in
            guard let value else { return nil }
            return BatchUpsertService.Row(holdingId: key, amount: value)
        }
        do {
            try BatchUpsertService.apply(rows, periodMonth: normalized, context: context)
            savedOnce.formUnion(rows.map(\.holdingId))
            edits.removeAll()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatAmount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    private func isoCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }
}

#Preview {
    BatchEntryView()
        .modelContainer(PersistenceController.previewContainer())
}

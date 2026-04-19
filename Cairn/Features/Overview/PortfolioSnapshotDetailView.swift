import SwiftUI
import SwiftData

/// Read-only detail for a captured `PortfolioSnapshot`.
struct PortfolioSnapshotDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let snapshot: PortfolioSnapshot

    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                if !snapshot.entries.isEmpty {
                    entriesCard
                }
                if !snapshot.rates.isEmpty {
                    ratesCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground()
        .navigationTitle(titleText)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "portfolioSnapshot.delete.confirm.title",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                delete()
            } label: {
                Text("portfolioSnapshot.delete.confirm.action")
            }
            Button(role: .cancel) {} label: { Text("common.action.cancel") }
        } message: {
            Text("portfolioSnapshot.delete.confirm.message")
        }
        .alert(
            "portfolioSnapshot.delete.failure",
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

    private var titleText: String {
        snapshot.periodMonth.formatted(.dateTime.year().month(.wide).locale(locale))
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("portfolioSnapshot.detail.total")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: snapshot.homeCurrency)
                    .font(.caption.monospaced().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            Text(snapshot.totalAmount, format: .currency(code: snapshot.homeCurrency).locale(locale))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(capturedFootnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let note = snapshot.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var entriesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("portfolioSnapshot.detail.breakdown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(memberGroups, id: \.member) { group in
                memberGroupSection(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func memberGroupSection(_ group: MemberGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: group.member)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    entryRow(entry)
                    if index < group.entries.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: PortfolioSnapshot.Entry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.accountName)
                    .font(.callout.weight(.semibold))
                HStack(spacing: 6) {
                    Text(verbatim: entry.currency)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                    if let label = entry.holdingLabel, !label.isEmpty {
                        Text(verbatim: label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.amount, format: .currency(code: entry.currency).locale(locale))
                    .font(.callout.monospacedDigit().weight(.semibold))
                if entry.currency != snapshot.homeCurrency {
                    if let converted = entry.convertedAmount {
                        Text(converted, format: .currency(code: snapshot.homeCurrency).locale(locale))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("portfolioSnapshot.detail.currency.noRate")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    /// Entries grouped by member in stable display order: members sorted
    /// by name, and entries within each member sorted by account name
    /// then currency so multi-currency accounts cluster together.
    private var memberGroups: [MemberGroup] {
        let grouped = Dictionary(grouping: snapshot.entries, by: { $0.memberName })
        return grouped.keys.sorted().map { member in
            let entries = (grouped[member] ?? []).sorted { lhs, rhs in
                if lhs.accountName == rhs.accountName {
                    return lhs.currency < rhs.currency
                }
                return lhs.accountName < rhs.accountName
            }
            return MemberGroup(member: member, entries: entries)
        }
    }

    private struct MemberGroup {
        let member: String
        let entries: [PortfolioSnapshot.Entry]
    }

    private var ratesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("portfolioSnapshot.detail.rates")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(Array(normalizedRates.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(verbatim: row.display)
                            .font(.callout.monospaced())
                        Spacer()
                        Text(verbatim: row.valueDisplay(locale: locale))
                            .font(.callout.monospacedDigit())
                    }
                    .padding(.vertical, 8)
                    if index < normalizedRates.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Renders every captured rate as `1 foreign = X home` so the reader
    /// always sees the conversion factor in the same direction.
    private var normalizedRates: [DisplayRate] {
        snapshot.rates.compactMap { rate in
            if rate.quote == snapshot.homeCurrency {
                return DisplayRate(
                    foreign: rate.base,
                    home: snapshot.homeCurrency,
                    valuePerUnit: rate.rate
                )
            }
            if rate.base == snapshot.homeCurrency, rate.rate != 0 {
                return DisplayRate(
                    foreign: rate.quote,
                    home: snapshot.homeCurrency,
                    valuePerUnit: 1 / rate.rate
                )
            }
            return nil
        }
        .sorted { $0.foreign < $1.foreign }
    }

    private struct DisplayRate: Identifiable {
        let foreign: String
        let home: String
        let valuePerUnit: Decimal
        var id: String { "\(foreign)->\(home)" }
        var display: String { "1 \(foreign) → \(home)" }
        func valueDisplay(locale: Locale) -> String {
            valuePerUnit.formatted(.number.precision(.fractionLength(2...6)).locale(locale))
        }
    }

    private var capturedFootnote: String {
        let template = String(localized: "portfolioSnapshot.detail.capturedAt")
        let date = snapshot.recordedAt.formatted(.dateTime.year().month().day().locale(locale))
        return template.replacingOccurrences(of: "{date}", with: date)
    }

    private func delete() {
        do {
            try PortfolioSnapshotService.delete(snapshot, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        PortfolioSnapshotDetailView(snapshot: env.seed.latestPortfolioSnapshot)
    }
    .modelContainer(env.container)
}

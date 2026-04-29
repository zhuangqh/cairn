import SwiftUI
import SwiftData

/// Snapshot timeline for a single `Account`. Reached by tapping an account
/// card from the expanded member section on `MembersListView`. Hosts the
/// account's primary holding, lets the user add/edit snapshots, filter by
/// year, and edit the underlying account or holding from the toolbar.
struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var editingSnapshot: Snapshot?
    @State private var snapshotPendingDeletion: Snapshot?
    @State private var editingAccount = false
    @State private var editingHolding = false
    @State private var selectedYear: Int? = nil
    @State private var didInitFilter = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                headerCard
                if let primary = primaryHolding {
                    Section {
                        snapshotList(for: primary)
                            .padding(.top, 4)
                    } header: {
                        snapshotFilterHeader(for: primary)
                    }
                } else {
                    emptyHoldingCard
                }
            }
            .pageHorizontalPadding()
            .padding(.vertical, 20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground()
        .navigationTitle(Text(verbatim: account.name.isEmpty ? " " : account.name))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { primeSelectedYear() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editingAccount = true
                    } label: {
                        Label {
                            Text("account.edit.title")
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    if primaryHolding != nil {
                        Button {
                            editingHolding = true
                        } label: {
                            Label {
                                Text("holding.edit.title")
                            } icon: {
                                Image(systemName: "tag")
                            }
                        }
                    }
                    if let primary = primaryHolding {
                        Button {
                            primary.isArchived.toggle()
                        } label: {
                            Label {
                                Text(primary.isArchived ? "common.action.unarchive" : "common.action.archive")
                            } icon: {
                                Image(systemName: primary.isArchived ? "tray.and.arrow.up" : "archivebox")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editingSnapshot) { snapshot in
            if let primary = primaryHolding {
                SnapshotFormView(holding: primary, existing: snapshot)
            }
        }
        .sheet(isPresented: $editingAccount) {
            AccountFormView(account: account, isNew: false)
        }
        .sheet(isPresented: $editingHolding) {
            if let primary = primaryHolding {
                HoldingEditView(holding: primary)
            }
        }
        .alert(
            Text("snapshot.delete.confirm.title"),
            isPresented: Binding(
                get: { snapshotPendingDeletion != nil },
                set: { if !$0 { snapshotPendingDeletion = nil } }
            ),
            presenting: snapshotPendingDeletion
        ) { snapshot in
            Button(role: .destructive) {
                context.delete(snapshot)
                snapshotPendingDeletion = nil
            } label: {
                Text("common.action.delete")
            }
            Button(role: .cancel) {
                snapshotPendingDeletion = nil
            } label: {
                Text("common.action.cancel")
            }
        } message: { _ in
            Text("snapshot.delete.confirm.message")
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        HStack(spacing: 14) {
            GlyphBadge(systemName: account.kind.iconName, tint: account.kind.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(account.kind.localizationKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if let note = account.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if account.isArchived {
                        Text("common.label.archived")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.18), in: Capsule())
                    }
                    ForEach(activeCurrencies.prefix(3), id: \.self) { code in
                        Text(verbatim: code)
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(account.kind.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(account.kind.tint)
                    }
                }
            }
            Spacer()
            if let primary = primaryHolding, let latest = sortedSnapshots(for: primary).first {
                Text(
                    latest.amount,
                    format: .currency(code: primary.currency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.title3.monospacedDigit().weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var emptyHoldingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("holding.empty")
                .font(.callout.weight(.medium))
            Text("holding.empty.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func snapshotFilterHeader(for holding: Holding) -> some View {
        HStack {
            Text("account.detail.snapshots")
                .font(.headline)
            Spacer()
            yearFilterMenu(for: holding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(LiquidGlassBackground(cornerRadius: 14))
    }

    @ViewBuilder
    private func yearFilterMenu(for holding: Holding) -> some View {
        let years = availableYears(for: holding)
        if !years.isEmpty {
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
                ForEach(years, id: \.self) { year in
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

    @ViewBuilder
    private func snapshotList(for holding: Holding) -> some View {
        let snapshots = filteredSnapshots(for: holding)
        if snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("snapshot.empty")
                    .font(.callout.weight(.medium))
                Text("snapshot.empty.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    AccountSnapshotRow(
                        snapshot: snapshot,
                        previous: index + 1 < snapshots.count ? snapshots[index + 1] : nil,
                        currency: holding.currency,
                        locale: locale
                    )
                    .onTapGesture {
                        editingSnapshot = snapshot
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            snapshotPendingDeletion = snapshot
                        } label: {
                            Label {
                                Text("common.action.delete")
                            } icon: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var activeCurrencies: [String] {
        var seen: Set<String> = []
        return (account.holdings ?? [])
            .filter { !$0.isArchived }
            .map(\.currency)
            .filter { seen.insert($0).inserted }
    }

    private var primaryHolding: Holding? {
        let all = account.holdings ?? []
        return all.first { !$0.isArchived }
            ?? all.sorted { $0.createdAt < $1.createdAt }.first
    }

    private func sortedSnapshots(for holding: Holding) -> [Snapshot] {
        (holding.snapshots ?? []).sorted { $0.periodMonth > $1.periodMonth }
    }

    private func availableYears(for holding: Holding) -> [Int] {
        let calendar = Calendar.current
        let years = Set((holding.snapshots ?? []).map { calendar.component(.year, from: $0.periodMonth) })
        return years.sorted(by: >)
    }

    private func filteredSnapshots(for holding: Holding) -> [Snapshot] {
        let all = sortedSnapshots(for: holding)
        guard let selectedYear else { return all }
        let calendar = Calendar.current
        return all.filter { calendar.component(.year, from: $0.periodMonth) == selectedYear }
    }

    private func primeSelectedYear() {
        guard !didInitFilter else { return }
        didInitFilter = true
        guard let holding = primaryHolding,
              let latest = availableYears(for: holding).first else { return }
        selectedYear = latest
    }
}

private struct AccountSnapshotRow: View {
    let snapshot: Snapshot
    let previous: Snapshot?
    let currency: String
    let locale: Locale

    private var delta: Decimal? {
        guard let previous else { return nil }
        return snapshot.amount - previous.amount
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.periodMonth, format: .dateTime.year().locale(locale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(snapshot.periodMonth, format: .dateTime.month(.wide).locale(locale))
                    .font(.callout.weight(.semibold))
            }
            .frame(width: 96, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    snapshot.amount,
                    format: .currency(code: currency).locale(locale)
                )
                .font(.callout.monospacedDigit().weight(.semibold))

                if let delta, delta != 0 {
                    let positive = delta >= 0
                    HStack(spacing: 2) {
                        Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                        Text(
                            delta,
                            format: .currency(code: currency).locale(locale).precision(.fractionLength(0))
                        )
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(positive ? Color.green : Color.red)
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("AccountDetail · seeded") {
    let env = PreviewSampleData.seededContainer()
    let account = (env.seed.alice.accounts ?? []).first ?? Account(name: "Demo", kind: .cash, member: env.seed.alice)
    return NavigationStack {
        AccountDetailView(account: account)
    }
    .modelContainer(env.container)
}
#endif

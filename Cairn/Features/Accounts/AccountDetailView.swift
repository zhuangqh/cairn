import SwiftUI
import SwiftData

/// Shows an account's snapshots directly. Every account owns a single
/// currency chosen at creation time, so we inline the primary holding's
/// snapshot list here instead of presenting a redundant "pick currency"
/// layer.
struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var presentingSnapshotForm = false
    @State private var editingSnapshot: Snapshot?
    @State private var snapshotPendingDeletion: Snapshot?
    @State private var editingAccount = false
    @State private var editingHolding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let primary = primaryHolding {
                    summaryCard(primary)
                    snapshotSection(primary)
                } else {
                    ContentUnavailableView(
                        "holding.empty",
                        systemImage: "coloncurrencysign.circle",
                        description: Text("holding.empty.hint")
                    )
                    .padding(.top, 64)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground()
        .navigationTitle(Text(verbatim: account.name))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if primaryHolding != nil {
                        Button {
                            presentingSnapshotForm = true
                        } label: {
                            Label {
                                Text("snapshot.new.title")
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    Button {
                        editingAccount = true
                    } label: {
                        Label {
                            Text("account.edit.title")
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    if let primary = primaryHolding {
                        Button {
                            editingHolding = true
                        } label: {
                            Label {
                                Text("holding.edit.title")
                            } icon: {
                                Image(systemName: "tag")
                            }
                        }
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
        .sheet(isPresented: $presentingSnapshotForm) {
            if let primary = primaryHolding {
                SnapshotFormView(holding: primary, existing: nil)
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
        .confirmationDialog(
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

    // MARK: - Sections

    private func summaryCard(_ holding: Holding) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                account.kind.tint.opacity(0.9),
                                account.kind.tint.opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(verbatim: holding.currency)
                    .font(.callout.monospaced().weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CurrencyCatalog.displayName(holding.currency))
                    .font(.headline)
                if let label = holding.label, !label.isEmpty {
                    Text(verbatim: label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let latest = sortedSnapshots(for: holding).first {
                Text(
                    latest.amount,
                    format: .currency(code: holding.currency).locale(locale)
                )
                .font(.title2.monospacedDigit().weight(.semibold))
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func snapshotSection(_ holding: Holding) -> some View {
        let snapshots = sortedSnapshots(for: holding)
        if snapshots.isEmpty {
            ContentUnavailableView(
                "snapshot.empty",
                systemImage: "calendar",
                description: Text("snapshot.empty.hint")
            )
            .glassCard()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .foregroundStyle(account.kind.tint)
                    Text("holding.detail.snapshots")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 4)

                VStack(spacing: 10) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        SnapshotRow(
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
    }

    // MARK: - Derived

    private var primaryHolding: Holding? {
        let all = account.holdings ?? []
        return all.first { !$0.isArchived }
            ?? all.sorted { $0.createdAt < $1.createdAt }.first
    }

    private func sortedSnapshots(for holding: Holding) -> [Snapshot] {
        (holding.snapshots ?? []).sorted { $0.periodMonth > $1.periodMonth }
    }
}

private struct SnapshotRow: View {
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
        .glassCard(cornerRadius: 14, padding: 14)
    }
}

#Preview("AccountDetail · populated") {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        AccountDetailView(account: env.seed.checking)
    }
    .modelContainer(env.container)
}

#Preview("AccountDetail · empty account") {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        AccountDetailView(account: env.seed.emptyAccount)
    }
    .modelContainer(env.container)
}

import SwiftUI
import SwiftData

struct HoldingDetailView: View {
    @Bindable var holding: Holding
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var presentingSnapshotForm = false
    @State private var editingSnapshot: Snapshot?
    @State private var snapshotPendingDeletion: Snapshot?
    @State private var editingLabel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard

                if (holding.snapshots ?? []).isEmpty {
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
                                .foregroundStyle(holding.account?.kind.tint ?? .accentColor)
                            Text("holding.detail.snapshots")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 10) {
                            ForEach(Array(sortedSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                                SnapshotCard(
                                    snapshot: snapshot,
                                    previous: index + 1 < sortedSnapshots.count ? sortedSnapshots[index + 1] : nil,
                                    currency: holding.currency,
                                    tint: holding.account?.kind.tint ?? .accentColor,
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
            .pageHorizontalPadding()
            .padding(.vertical, 20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground()
        .navigationTitle(Text(verbatim: titleText))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        presentingSnapshotForm = true
                    } label: {
                        Label {
                            Text("snapshot.new.title")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    Button {
                        editingLabel = true
                    } label: {
                        Label {
                            Text("holding.edit.title")
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    Button {
                        holding.isArchived.toggle()
                    } label: {
                        Label {
                            Text(holding.isArchived ? "common.action.unarchive" : "common.action.archive")
                        } icon: {
                            Image(systemName: holding.isArchived ? "tray.and.arrow.up" : "archivebox")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $presentingSnapshotForm) {
            SnapshotFormView(holding: holding, existing: nil)
        }
        .sheet(item: $editingSnapshot) { snapshot in
            SnapshotFormView(holding: holding, existing: snapshot)
        }
        .sheet(isPresented: $editingLabel) {
            HoldingEditView(holding: holding)
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

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                (holding.account?.kind.tint ?? .accentColor).opacity(0.9),
                                (holding.account?.kind.tint ?? .accentColor).opacity(0.55)
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

            if let latest = sortedSnapshots.first {
                Text(
                    latest.amount,
                    format: .currency(code: holding.currency).locale(locale)
                )
                .font(.title2.monospacedDigit().weight(.semibold))
            }
        }
        .glassCard()
    }

    private var titleText: String {
        if let label = holding.label, !label.isEmpty {
            return "\(holding.currency) · \(label)"
        }
        return holding.currency
    }

    private var sortedSnapshots: [Snapshot] {
        (holding.snapshots ?? []).sorted { $0.periodMonth > $1.periodMonth }
    }
}

private struct SnapshotCard: View {
    let snapshot: Snapshot
    let previous: Snapshot?
    let currency: String
    let tint: Color
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

#Preview("HoldingDetail · with snapshots") {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        HoldingDetailView(holding: env.seed.brokerageUSD)
    }
    .modelContainer(env.container)
}

#Preview("HoldingDetail · empty") {
    let env = PreviewSampleData.seededContainer()
    let empty = Holding(currency: "JPY", label: "Yen", account: env.seed.checking)
    env.container.mainContext.insert(empty)
    return NavigationStack {
        HoldingDetailView(holding: empty)
    }
    .modelContainer(env.container)
}

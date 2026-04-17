import SwiftUI
import SwiftData

struct HoldingDetailView: View {
    @Bindable var holding: Holding
    @Environment(\.modelContext) private var context

    @State private var presentingSnapshotForm = false
    @State private var editingSnapshot: Snapshot?
    @State private var snapshotPendingDeletion: Snapshot?
    @State private var editingLabel = false

    var body: some View {
        Group {
            if (holding.snapshots ?? []).isEmpty {
                ContentUnavailableView(
                    "snapshot.empty",
                    systemImage: "calendar",
                    description: Text("snapshot.empty.hint")
                )
            } else {
                List {
                    Section {
                        ForEach(sortedSnapshots) { snapshot in
                            SnapshotRow(snapshot: snapshot, currency: holding.currency)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingSnapshot = snapshot
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        snapshotPendingDeletion = snapshot
                                    } label: {
                                        Label("common.action.delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text("holding.detail.snapshots")
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: titleText))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        presentingSnapshotForm = true
                    } label: {
                        Label("snapshot.new.title", systemImage: "plus")
                    }
                    Button {
                        editingLabel = true
                    } label: {
                        Label("holding.edit.title", systemImage: "pencil")
                    }
                    Button {
                        holding.isArchived.toggle()
                    } label: {
                        Label(
                            holding.isArchived ? "common.action.unarchive" : "common.action.archive",
                            systemImage: holding.isArchived ? "tray.and.arrow.up" : "archivebox"
                        )
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

private struct SnapshotRow: View {
    let snapshot: Snapshot
    let currency: String

    var body: some View {
        HStack {
            Text(snapshot.periodMonth, format: .dateTime.year().month())
                .monospacedDigit()
            Spacer()
            Text(snapshot.amount, format: .currency(code: currency))
                .monospacedDigit()
        }
    }
}

import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var context

    @State private var presentingHoldingForm = false
    @State private var holdingPendingDeletion: Holding?
    @State private var editingAccount = false
    @State private var errorMessageKey: String?

    var body: some View {
        Group {
            if (account.holdings ?? []).isEmpty {
                ContentUnavailableView(
                    "holding.empty",
                    systemImage: "coloncurrencysign.circle",
                    description: Text("holding.empty.hint")
                )
            } else {
                List {
                    Section {
                        ForEach(sortedHoldings) { holding in
                            NavigationLink(value: holding) {
                                HoldingRow(holding: holding)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    holdingPendingDeletion = holding
                                } label: {
                                    Label("common.action.delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("account.detail.holdings")
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: account.name))
        .navigationDestination(for: Holding.self) { holding in
            HoldingDetailView(holding: holding)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        presentingHoldingForm = true
                    } label: {
                        Label("holding.new.title", systemImage: "plus")
                    }
                    Button {
                        editingAccount = true
                    } label: {
                        Label("account.edit.title", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $presentingHoldingForm) {
            HoldingCreateView(account: account) { error in
                if let error {
                    errorMessageKey = error.localizationKey
                }
            }
        }
        .sheet(isPresented: $editingAccount) {
            AccountFormView(account: account, isNew: false)
        }
        .alert(
            Text("common.action.save"),
            isPresented: Binding(
                get: { errorMessageKey != nil },
                set: { if !$0 { errorMessageKey = nil } }
            ),
            presenting: errorMessageKey
        ) { _ in
            Button(role: .cancel) {
                errorMessageKey = nil
            } label: {
                Text("common.action.done")
            }
        } message: { key in
            Text(LocalizedStringKey(key))
        }
        .confirmationDialog(
            Text("holding.delete.confirm.title"),
            isPresented: Binding(
                get: { holdingPendingDeletion != nil },
                set: { if !$0 { holdingPendingDeletion = nil } }
            ),
            presenting: holdingPendingDeletion
        ) { holding in
            Button(role: .destructive) {
                context.delete(holding)
                holdingPendingDeletion = nil
            } label: {
                Text("common.action.delete")
            }
            Button(role: .cancel) {
                holdingPendingDeletion = nil
            } label: {
                Text("common.action.cancel")
            }
        } message: { _ in
            Text("holding.delete.confirm.message")
        }
    }

    private var sortedHoldings: [Holding] {
        (account.holdings ?? []).sorted { lhs, rhs in
            if lhs.isArchived != rhs.isArchived {
                return !lhs.isArchived
            }
            return lhs.currency < rhs.currency
        }
    }
}

private struct HoldingRow: View {
    let holding: Holding

    var body: some View {
        HStack {
            Text(verbatim: holding.currency)
                .font(.headline)
                .frame(minWidth: 48, alignment: .leading)
            VStack(alignment: .leading) {
                Text(verbatim: CurrencyCatalog.displayName(holding.currency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let label = holding.label, !label.isEmpty {
                    Text(verbatim: label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let latest = latestSnapshot {
                Text(latest.amount, format: .currency(code: holding.currency))
                    .monospacedDigit()
            }
            if holding.isArchived {
                Image(systemName: "archivebox")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var latestSnapshot: Snapshot? {
        (holding.snapshots ?? []).sorted(by: { $0.periodMonth > $1.periodMonth }).first
    }
}

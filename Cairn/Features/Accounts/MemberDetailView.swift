import SwiftUI
import SwiftData

/// Lists the accounts belonging to a given `Member`, grouped by kind.
struct MemberDetailView: View {
    @Bindable var member: Member
    @Environment(\.modelContext) private var context

    @State private var newAccountDraft: Account?
    @State private var accountPendingDeletion: Account?
    @State private var editingMember = false

    var body: some View {
        Group {
            if (member.accounts ?? []).isEmpty {
                ContentUnavailableView(
                    "account.empty",
                    systemImage: "wallet.pass",
                    description: Text("account.empty.hint")
                )
            } else {
                List {
                    ForEach(AccountKind.allCases, id: \.self) { kind in
                        let bucket = accounts(for: kind)
                        if !bucket.isEmpty {
                            Section {
                                ForEach(bucket) { account in
                                    NavigationLink(value: account) {
                                        AccountRow(account: account)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            accountPendingDeletion = account
                                        } label: {
                                            Label("common.action.delete", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(LocalizedStringKey(kind.localizationKey))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: member.name))
        .navigationDestination(for: Account.self) { account in
            AccountDetailView(account: account)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        let draft = Account(name: "", kind: .cash, member: member)
                        context.insert(draft)
                        newAccountDraft = draft
                    } label: {
                        Label("account.new.title", systemImage: "plus")
                    }
                    Button {
                        editingMember = true
                    } label: {
                        Label("member.edit.title", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $newAccountDraft) { draft in
            AccountFormView(account: draft, isNew: true) { saved in
                if !saved {
                    context.delete(draft)
                }
            }
        }
        .sheet(isPresented: $editingMember) {
            MemberFormView(member: member, isNew: false)
        }
        .confirmationDialog(
            Text("account.delete.confirm.title"),
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            presenting: accountPendingDeletion
        ) { account in
            Button(role: .destructive) {
                context.delete(account)
                accountPendingDeletion = nil
            } label: {
                Text("common.action.delete")
            }
            Button(role: .cancel) {
                accountPendingDeletion = nil
            } label: {
                Text("common.action.cancel")
            }
        } message: { _ in
            Text("account.delete.confirm.message")
        }
    }

    private func accounts(for kind: AccountKind) -> [Account] {
        (member.accounts ?? [])
            .filter { $0.kind == kind }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

private struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack {
            Image(systemName: account.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(verbatim: account.name.isEmpty ? " " : account.name)
                if account.isArchived {
                    Text("common.label.archived")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(verbatim: currencySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currencySummary: String {
        let codes = (account.holdings ?? [])
            .filter { !$0.isArchived }
            .map(\.currency)
            .uniqued()
        return codes.joined(separator: " · ")
    }
}

private extension AccountKind {
    var symbolName: String {
        switch self {
        case .cash: return "banknote"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .realEstate: return "house"
        case .device: return "laptopcomputer"
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

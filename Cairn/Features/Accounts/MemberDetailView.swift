import SwiftUI
import SwiftData

/// Lists the accounts belonging to a given `Member`, grouped by kind.
/// Uses translucent cards and kind-colored leading badges to match the
/// rest of the Liquid Glass surfaces.
struct MemberDetailView: View {
    @Bindable var member: Member
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var newAccountDraft: Account?
    @State private var accountPendingDeletion: Account?
    @State private var editingMember = false

    var body: some View {
        ScrollView {
            if (member.accounts ?? []).isEmpty {
                ContentUnavailableView(
                    "account.empty",
                    systemImage: "wallet.pass",
                    description: Text("account.empty.hint")
                )
                .padding(.top, 64)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(AccountKind.allCases, id: \.self) { kind in
                        let bucket = accounts(for: kind)
                        if !bucket.isEmpty {
                            kindSection(for: kind, accounts: bucket)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .ambientBackground()
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
                        Label {
                            Text("account.new.title")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    Button {
                        editingMember = true
                    } label: {
                        Label {
                            Text("member.edit.title")
                        } icon: {
                            Image(systemName: "pencil")
                        }
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

    // MARK: - Sections

    @ViewBuilder
    private func kindSection(for kind: AccountKind, accounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: kind.iconName)
                    .foregroundStyle(kind.tint)
                Text(LocalizedStringKey(kind.localizationKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(accounts) { account in
                    NavigationLink(value: account) {
                        AccountCard(account: account, tint: kind.tint, locale: locale)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            accountPendingDeletion = account
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

    private func accounts(for kind: AccountKind) -> [Account] {
        (member.accounts ?? [])
            .filter { $0.kind == kind }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

private struct AccountCard: View {
    let account: Account
    let tint: Color
    let locale: Locale

    private var activeCurrencies: [String] {
        var seen: Set<String> = []
        return (account.holdings ?? [])
            .filter { !$0.isArchived }
            .map(\.currency)
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        HStack(spacing: 14) {
            GlyphBadge(systemName: account.kind.iconName, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: account.name.isEmpty ? " " : account.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    if account.isArchived {
                        Text("common.label.archived")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.18), in: Capsule())
                    }
                    if let note = account.note, !note.isEmpty {
                        Text(verbatim: note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(activeCurrencies.prefix(3), id: \.self) { code in
                    Text(verbatim: code)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .glassCard(cornerRadius: 14, padding: 14)
    }
}

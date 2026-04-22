import SwiftUI
import SwiftData

/// Detail view for a `Member`: shows the account list grouped by kind.
/// Tapping an account navigates deeper to `AccountDetailView`. Toolbar
/// provides edit-member and new-account actions.
struct MemberDetailView: View {
    @Bindable var member: Member
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var editingMember = false
    @State private var newAccountDraft: Account?
    @State private var pendingAccountDraft: Account?
    @State private var didSaveAccountDraft = false
    @State private var accountPendingDeletion: Account?

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
        .navigationTitle(Text(verbatim: member.name.isEmpty ? " " : member.name))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        newAccountDraft = makeAccountDraft()
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
        .sheet(isPresented: $editingMember) {
            MemberFormView(member: member, isNew: false)
        }
        .sheet(item: $newAccountDraft, onDismiss: {
            if !didSaveAccountDraft, let draft = pendingAccountDraft {
                // Sheet was swiped away without tapping Save; roll back the
                // draft so a stray empty account doesn't linger.
                context.delete(draft)
            }
            pendingAccountDraft = nil
            didSaveAccountDraft = false
        }) { draft in
            AccountFormView(account: draft, isNew: true) { saved in
                didSaveAccountDraft = saved
                if !saved {
                    context.delete(draft)
                    pendingAccountDraft = nil
                }
            }
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
                        MemberAccountRow(account: account, tint: kind.tint, locale: locale)
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

    private func makeAccountDraft() -> Account {
        let draft = Account(name: "", kind: .cash, member: member)
        context.insert(draft)
        pendingAccountDraft = draft
        didSaveAccountDraft = false
        return draft
    }

    private func cleanupUnsavedDraft() {
        guard let draft = pendingAccountDraft else { return }
        context.delete(draft)
        pendingAccountDraft = nil
    }
}

struct MemberAccountRow: View {
    @Bindable var account: Account
    let tint: Color
    let locale: Locale

    private var primaryHolding: Holding? {
        let all = account.holdings ?? []
        return all.first { !$0.isArchived }
            ?? all.sorted { $0.createdAt < $1.createdAt }.first
    }

    private var activeCurrencies: [String] {
        var seen: Set<String> = []
        return (account.holdings ?? [])
            .filter { !$0.isArchived }
            .map(\.currency)
            .filter { seen.insert($0).inserted }
    }

    private var latestSnapshot: Snapshot? {
        guard let primary = primaryHolding else { return nil }
        return (primary.snapshots ?? []).sorted { $0.periodMonth > $1.periodMonth }.first
    }

    var body: some View {
        HStack(spacing: 14) {
            GlyphBadge(systemName: account.kind.iconName, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: account.name.isEmpty ? " " : account.name)
                    .font(.callout.weight(.semibold))
                HStack(spacing: 6) {
                    if account.isArchived {
                        Text("common.label.archived")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.18), in: Capsule())
                    }
                    ForEach(activeCurrencies.prefix(2), id: \.self) { code in
                        Text(verbatim: code)
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(tint)
                    }
                }
            }

            Spacer()

            if let primary = primaryHolding, let latest = latestSnapshot {
                Text(
                    latest.amount,
                    format: .currency(code: primary.currency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.callout.monospacedDigit().weight(.semibold))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("MemberDetail · seeded") {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        MemberDetailView(member: env.seed.alice)
    }
    .modelContainer(env.container)
}
#endif

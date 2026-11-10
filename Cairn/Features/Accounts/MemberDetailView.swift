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
            VStack(alignment: .leading, spacing: 0) {
                memberHeader

                if (member.accounts ?? []).isEmpty {
                    ContentUnavailableView(
                        "account.empty",
                        systemImage: "wallet.pass",
                        description: Text("account.empty.hint")
                    )
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(AccountKind.allCases, id: \.self) { kind in
                        let bucket = accounts(for: kind)
                        if !bucket.isEmpty {
                            kindSection(for: kind, accounts: bucket)
                        }
                    }
                }
            }
            .pageHorizontalPadding()
            .padding(.bottom, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
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
        .alert(
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
    private var memberHeader: some View {
        VStack(spacing: 12) {
            MemberAvatarView(
                name: member.name,
                avatarData: member.avatarData,
                seed: member.id,
                size: 96
            )
            VStack(spacing: 4) {
                Text(verbatim: member.name.isEmpty ? " " : member.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(verbatim: String(localized: "assets.member.accountCount \((member.accounts ?? []).count)"))
                    .font(.subheadline)
                    .foregroundStyle(Color.ink3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private func kindSection(for kind: AccountKind, accounts: [Account]) -> some View {
        LedgerSection(Text(LocalizedStringKey(kind.localizationKey))) {
            LedgerRows(data: accounts, inset: LedgerMetrics.leadingColumn + LedgerMetrics.columnSpacing) { account in
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

    /// Ledger row (§4): glyph tile / name with kind and currencies / latest
    /// balance of the primary holding / chevron.
    var body: some View {
        HStack(spacing: LedgerMetrics.columnSpacing) {
            LedgerGlyphTile(systemName: account.kind.iconName, size: 30)
                .frame(width: LedgerMetrics.leadingColumn, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.name.isEmpty ? " " : account.name)
                    .font(.callout)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(verbatim: captionLine)
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let primary = primaryHolding, let latest = latestSnapshot {
                Text(
                    latest.amount,
                    format: .currency(code: primary.currency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .fixedSize()
            }

            LedgerChevron()
        }
        .padding(.vertical, 6)
        .frame(minHeight: LedgerMetrics.rowHeight + 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Cash · USD, EUR" (plus "Archived" when relevant).
    private var captionLine: String {
        var parts = [String(localized: String.LocalizationValue(account.kind.localizationKey))]
        if !activeCurrencies.isEmpty {
            parts.append(activeCurrencies.formatted(.list(type: .and).locale(locale)))
        }
        if account.isArchived {
            parts.append(String(localized: "common.label.archived"))
        }
        return parts.joined(separator: " · ")
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

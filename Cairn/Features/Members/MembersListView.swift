import SwiftUI
import SwiftData

/// Lists every `Member`. Tapping the row navigates to
/// `MemberDetailView` (account list). A trailing chevron button on each
/// card also lets the user expand an inline preview of the accounts
/// without leaving the list.
struct MembersListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]

    @State private var newMemberDraft: Member?
    @State private var memberPendingDeletion: Member?
    @State private var expandedMemberIDs: Set<UUID> = []
    @State private var editingMember: Member?

    private var memberTotals: [UUID: Decimal] {
        _ = holdings.count + snapshots.count + rates.count + members.count
        let bundle = NetWorthCalculator.bundle(
            homeCurrency: homeCurrency,
            includeMemberBreakdown: true,
            context: context
        )
        var dict: [UUID: Decimal] = [:]
        dict.reserveCapacity(bundle.byMember.count)
        for entry in bundle.byMember { dict[entry.memberId] = entry.amount }
        return dict
    }

    var body: some View {
        let totals = memberTotals
        return ScrollView {
            if members.isEmpty {
                ContentUnavailableView(
                    "member.empty",
                    systemImage: "person.2",
                    description: Text("member.empty.hint")
                )
                .padding(.top, 64)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(members) { member in
                        MemberRowCard(
                            member: member,
                            total: totals[member.id] ?? 0,
                            homeCurrency: homeCurrency,
                            locale: locale,
                            isExpanded: expandedMemberIDs.contains(member.id),
                            toggle: { toggle(member: member) },
                            onEditMember: { editingMember = member },
                            onDeleteMember: { memberPendingDeletion = member }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .ambientBackground()
        .navigationTitle("members.title")
        .navigationDestination(for: Member.self) { member in
            MemberDetailView(member: member)
        }
        .navigationDestination(for: Account.self) { account in
            AccountDetailView(account: account)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let draft = Member(name: "")
                    context.insert(draft)
                    newMemberDraft = draft
                } label: {
                    Label {
                        Text("common.action.add")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $newMemberDraft) { draft in
            MemberFormView(member: draft, isNew: true) { saved in
                if !saved {
                    context.delete(draft)
                }
            }
        }
        .sheet(item: $editingMember) { member in
            MemberFormView(member: member, isNew: false)
        }
        .confirmationDialog(
            Text("member.delete.confirm.title"),
            isPresented: Binding(
                get: { memberPendingDeletion != nil },
                set: { if !$0 { memberPendingDeletion = nil } }
            ),
            presenting: memberPendingDeletion
        ) { member in
            Button(role: .destructive) {
                context.delete(member)
                memberPendingDeletion = nil
            } label: {
                Text("common.action.delete")
            }
            Button(role: .cancel) {
                memberPendingDeletion = nil
            } label: {
                Text("common.action.cancel")
            }
        } message: { _ in
            Text("member.delete.confirm.message")
        }
    }

    private func toggle(member: Member) {
        withAnimation(.snappy) {
            if expandedMemberIDs.contains(member.id) {
                expandedMemberIDs.remove(member.id)
            } else {
                expandedMemberIDs.insert(member.id)
            }
        }
    }
}

// MARK: - Member row card

private struct MemberRowCard: View {
    @Bindable var member: Member
    let total: Decimal
    let homeCurrency: String
    let locale: Locale
    let isExpanded: Bool
    let toggle: () -> Void
    let onEditMember: () -> Void
    let onDeleteMember: () -> Void

    private var accountCount: Int {
        (member.accounts ?? []).count
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                NavigationLink(value: member) {
                    summaryContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        onEditMember()
                    } label: {
                        Label {
                            Text("member.edit.title")
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDeleteMember()
                    } label: {
                        Label {
                            Text("common.action.delete")
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }

                Button(action: toggle) {
                    Image(systemName: "chevron.down")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 32, height: 32)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isExpanded ? "common.action.collapse" : "common.action.expand"))
            }

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }

    private var summaryContent: some View {
        HStack(spacing: 16) {
            MemberAvatarView(
                name: member.name,
                avatarData: member.avatarData,
                seed: member.id,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: member.name.isEmpty ? " " : member.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(accountCount, format: .number)
                    Text("accounts.title")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(
                total,
                format: .currency(code: homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
            .font(.callout.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var expandedContent: some View {
        Divider().opacity(0.4)
        VStack(alignment: .leading, spacing: 8) {
            if sortedAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("account.empty")
                        .font(.callout.weight(.medium))
                    Text("account.empty.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(sortedAccounts) { account in
                    NavigationLink(value: account) {
                        MemberAccountRow(account: account, tint: account.kind.tint, locale: locale)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sortedAccounts: [Account] {
        (member.accounts ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

#Preview("MembersList · seeded") {
    NavigationStack {
        MembersListView()
    }
    .modelContainer(PreviewSampleData.container())
}

#Preview("MembersList · empty") {
    NavigationStack {
        MembersListView()
    }
    .modelContainer(PreviewSampleData.emptyContainer())
}

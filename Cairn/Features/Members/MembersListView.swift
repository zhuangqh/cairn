import SwiftUI
import SwiftData

/// Lists every `Member` with their accounts beneath (DESIGN.md §4). The
/// member header opens `MemberDetailView`; each account opens its detail.
struct MembersListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]

    @State private var newMemberDraft: Member?
    @State private var newMemberSaved: Bool = false
    /// Strong reference to the in-flight draft so we can delete it on
    /// dismissal (including interactive swipe-down on iOS, which does
    /// not fire the form's `onFinish` callback).
    @State private var pendingNewDraft: Member?
    @State private var memberPendingDeletion: Member?
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
        return ZStack {
            AppBackground()

            if members.isEmpty {
                ContentUnavailableView(
                    "member.empty",
                    systemImage: "person.2",
                    description: Text("member.empty.hint")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LedgerHero(
                            eyebrow: Text("members.total"),
                            amount: totals.values.reduce(0, +),
                            code: homeCurrency,
                            locale: locale,
                            showsDelta: false
                        ) {
                            Text(verbatim: String(localized: "assets.member.accountCount \(members.reduce(0) { $0 + ($1.accounts ?? []).count })"))
                        }
                        ForEach(members) { member in
                            MemberSection(
                                member: member,
                                total: totals[member.id] ?? 0,
                                homeCurrency: homeCurrency,
                                locale: locale,
                                onEditMember: { editingMember = member },
                                onDeleteMember: { memberPendingDeletion = member }
                            )
                        }
                    }
                    .pageHorizontalPadding()
                    .padding(.bottom, 24)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(Text("members.title", bundle: localization.bundle))
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
                    newMemberSaved = false
                    pendingNewDraft = draft
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
        .sheet(
            item: $newMemberDraft,
            onDismiss: {
                // Covers both explicit Cancel taps and interactive
                // swipe-down dismissal on iOS, which would otherwise
                // leave an empty draft member behind.
                if !newMemberSaved, let draft = pendingNewDraft {
                    context.delete(draft)
                }
                pendingNewDraft = nil
                newMemberSaved = false
            }
        ) { draft in
            MemberFormView(member: draft, isNew: true) { saved in
                newMemberSaved = saved
            }
        }
        .sheet(item: $editingMember) { member in
            MemberFormView(member: member, isNew: false)
        }
        .alert(
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
}

// MARK: - Member section

/// One member (§4): a hairline-ruled header row — avatar, name, account
/// count, total — followed by the member's accounts as ledger rows.
private struct MemberSection: View {
    @Bindable var member: Member
    let total: Decimal
    let homeCurrency: String
    let locale: Locale
    let onEditMember: () -> Void
    let onDeleteMember: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: member) {
                header
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

            if sortedAccounts.isEmpty {
                Text("account.empty.hint")
                    .font(.footnote)
                    .foregroundStyle(Color.ink3)
                    .padding(.bottom, 12)
            } else {
                LedgerRows(data: sortedAccounts, inset: LedgerMetrics.leadingColumn + LedgerMetrics.columnSpacing) { account in
                    NavigationLink(value: account) {
                        MemberAccountRow(account: account, tint: account.kind.tint, locale: locale)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .top) { LedgerHairline() }
    }

    private var header: some View {
        HStack(spacing: LedgerMetrics.columnSpacing) {
            MemberAvatarView(
                name: member.name,
                avatarData: member.avatarData,
                seed: member.id,
                size: 28
            )
            .frame(width: LedgerMetrics.leadingColumn, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: member.name.isEmpty ? " " : member.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text(verbatim: String(localized: "assets.member.accountCount \((member.accounts ?? []).count)"))
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(
                total,
                format: .currency(code: homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.ink)
            .fixedSize()
        }
        .frame(minHeight: LedgerMetrics.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var sortedAccounts: [Account] {
        (member.accounts ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

#Preview("MembersList · seeded") {
    NavigationStack {
        MembersListView()
    }
    .environment(LocalizationService())
    .modelContainer(PreviewSampleData.container())
}

#Preview("MembersList · empty") {
    NavigationStack {
        MembersListView()
    }
    .environment(LocalizationService())
    .modelContainer(PreviewSampleData.emptyContainer())
}

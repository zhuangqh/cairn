import SwiftUI
import SwiftData

/// Lists the accounts belonging to a given `Member`, grouped by kind.
/// Each account expands inline to reveal its holding's snapshots so the
/// user can review and edit balances without an extra navigation step.
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
                    ExpandableAccountRow(
                        account: account,
                        tint: kind.tint,
                        onDelete: { accountPendingDeletion = account }
                    )
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

// MARK: - Expandable account row

private struct ExpandableAccountRow: View {
    @Bindable var account: Account
    let tint: Color
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var isExpanded = false
    @State private var presentingSnapshotForm = false
    @State private var editingSnapshot: Snapshot?
    @State private var snapshotPendingDeletion: Snapshot?
    @State private var editingAccount = false
    @State private var editingHolding = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                summaryRow
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label {
                        Text("common.action.delete")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard(cornerRadius: 14, padding: 14)
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

    private var summaryRow: some View {
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

            if let primary = primaryHolding, let latest = sortedSnapshots(for: primary).first {
                Text(
                    latest.amount,
                    format: .currency(code: primary.currency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.callout.monospacedDigit().weight(.semibold))
            }

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var expandedContent: some View {
        Divider().opacity(0.4)
        if let primary = primaryHolding {
            VStack(alignment: .leading, spacing: 12) {
                actionBar(for: primary)
                snapshotList(for: primary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("holding.empty")
                    .font(.callout.weight(.medium))
                Text("holding.empty.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button {
                        editingAccount = true
                    } label: {
                        Label {
                            Text("account.edit.title")
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func actionBar(for holding: Holding) -> some View {
        HStack(spacing: 10) {
            Button {
                presentingSnapshotForm = true
            } label: {
                Label {
                    Text("snapshot.new.title")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer()

            Menu {
                Button {
                    editingAccount = true
                } label: {
                    Label {
                        Text("account.edit.title")
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
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
                    holding.isArchived.toggle()
                } label: {
                    Label {
                        Text(holding.isArchived ? "common.action.unarchive" : "common.action.archive")
                    } icon: {
                        Image(systemName: holding.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label {
                        Text("common.action.delete")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func snapshotList(for holding: Holding) -> some View {
        let snapshots = sortedSnapshots(for: holding)
        if snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("snapshot.empty")
                    .font(.callout.weight(.medium))
                Text("snapshot.empty.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 8) {
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

    // MARK: - Derived

    private var activeCurrencies: [String] {
        var seen: Set<String> = []
        return (account.holdings ?? [])
            .filter { !$0.isArchived }
            .map(\.currency)
            .filter { seen.insert($0).inserted }
    }

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
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

#Preview("MemberDetail · with accounts") {
    let env = PreviewSampleData.seededContainer()
    return NavigationStack {
        MemberDetailView(member: env.seed.alice)
    }
    .modelContainer(env.container)
}

#Preview("MemberDetail · empty") {
    let container = PreviewSampleData.emptyContainer()
    let blank = Member(name: "New member")
    container.mainContext.insert(blank)
    return NavigationStack {
        MemberDetailView(member: blank)
    }
    .modelContainer(container)
}

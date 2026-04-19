import SwiftUI
import SwiftData

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

    private var memberTotals: [UUID: Decimal] {
        _ = holdings.count + snapshots.count + rates.count
        return Dictionary(
            uniqueKeysWithValues: NetWorthCalculator
                .totalsByMember(homeCurrency: homeCurrency, context: context)
                .map { ($0.memberId, $0.amount) }
        )
    }

    var body: some View {
        ScrollView {
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
                        NavigationLink(value: member) {
                            MemberCard(
                                member: member,
                                total: memberTotals[member.id] ?? 0,
                                homeCurrency: homeCurrency,
                                locale: locale
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                memberPendingDeletion = member
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
}

private struct MemberCard: View {
    let member: Member
    let total: Decimal
    let homeCurrency: String
    let locale: Locale

    private var initials: String {
        let parts = member.name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var accountCount: Int {
        (member.accounts ?? []).count
    }

    private var tint: Color {
        let palette: [Color] = [.blue, .indigo, .teal, .pink, .orange, .purple, .green]
        let hash = abs(member.id.hashValue)
        return palette[hash % palette.count]
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(verbatim: initials)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

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

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    total,
                    format: .currency(code: homeCurrency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.title3.weight(.semibold).monospacedDigit())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard(cornerRadius: 16, padding: 16)
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

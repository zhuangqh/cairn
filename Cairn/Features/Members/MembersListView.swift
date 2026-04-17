import SwiftUI
import SwiftData

struct MembersListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.createdAt) private var members: [Member]

    @State private var newMemberDraft: Member?
    @State private var memberPendingDeletion: Member?

    var body: some View {
        Group {
            if members.isEmpty {
                ContentUnavailableView(
                    "member.empty",
                    systemImage: "person.2",
                    description: Text("member.empty.hint")
                )
            } else {
                List {
                    ForEach(members) { member in
                        NavigationLink(value: member) {
                            MemberRow(member: member)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                memberPendingDeletion = member
                            } label: {
                                Label("common.action.delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
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
                    Label("common.action.add", systemImage: "plus")
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

private struct MemberRow: View {
    let member: Member

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(verbatim: member.name)
                    .font(.body)
                HStack(spacing: 4) {
                    Text(activeAccountCount, format: .number)
                    Text("accounts.title")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var activeAccountCount: Int {
        (member.accounts ?? []).count
    }
}

#Preview {
    NavigationStack {
        MembersListView()
    }
    .modelContainer(PersistenceController.previewContainer())
}

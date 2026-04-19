import SwiftUI
import SwiftData

/// Edit form for a `Member`. When `isNew` is true, the caller is expected to
/// have already inserted an empty draft into the context; cancelling the form
/// invokes `onFinish(false)` so the caller can delete the draft.
struct MemberFormView: View {
    @Bindable var member: Member
    let isNew: Bool
    var onFinish: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("member.form.name", text: $member.name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("member.form.name")
                }
            }
            .formStyle(.grouped)
            .glassListStyle()
            .navigationTitle(isNew ? "member.new.title" : "member.edit.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        onFinish(false)
                        dismiss()
                    } label: {
                        Text("common.action.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onFinish(true)
                        dismiss()
                    } label: {
                        Text("common.action.save")
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        member.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import SwiftUI
import SwiftData

/// Create/edit form for an `Account`. Caller pre-inserts the draft when creating.
struct AccountFormView: View {
    @Bindable var account: Account
    let isNew: Bool
    var onFinish: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("account.form.name", text: $account.name)
                        .autocorrectionDisabled()
                }
                Section {
                    Picker(selection: Binding(
                        get: { account.kind },
                        set: { account.kind = $0 }
                    )) {
                        ForEach(AccountKind.allCases, id: \.self) { kind in
                            Text(LocalizedStringKey(kind.localizationKey))
                                .tag(kind)
                        }
                    } label: {
                        Text("account.form.kind")
                    }
                }
                Section {
                    TextField(
                        "account.form.note",
                        text: Binding(
                            get: { account.note ?? "" },
                            set: { account.note = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                }
            }
            .navigationTitle(isNew ? "account.new.title" : "account.edit.title")
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
        account.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

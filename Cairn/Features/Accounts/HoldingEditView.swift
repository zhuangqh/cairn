import SwiftUI
import SwiftData

/// Edit a Holding's non-currency fields. Currency is immutable (PRD §3.3).
struct HoldingEditView: View {
    @Bindable var holding: Holding
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text(verbatim: holding.currency)
                    } label: {
                        Text("currency.picker.title")
                    }
                }
                Section {
                    TextField(
                        "holding.form.label",
                        text: Binding(
                            get: { holding.label ?? "" },
                            set: { holding.label = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
            }
            .navigationTitle("holding.edit.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common.action.done")
                    }
                }
            }
        }
    }
}

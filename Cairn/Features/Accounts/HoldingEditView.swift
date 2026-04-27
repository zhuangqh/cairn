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
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundStyle(Color.notionInkSecondary)
                    } label: {
                        Text("currency.picker.title")
                    }
                } header: {
                    Text("currency.picker.title")
                } footer: {
                    Text("holding.edit.currencyImmutable.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField(
                        "holding.form.label",
                        text: Binding(
                            get: { holding.label ?? "" },
                            set: { holding.label = $0.isEmpty ? nil : $0 }
                        )
                    )
                } header: {
                    Text("holding.form.label")
                }
            }
            .formStyle(.grouped)
            .glassListStyle()
            .keyboardDismissable()
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

#Preview {
    let env = PreviewSampleData.seededContainer()
    return HoldingEditView(holding: env.seed.checkingEUR)
        .modelContainer(env.container)
}

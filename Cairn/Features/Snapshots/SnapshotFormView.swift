import SwiftUI
import SwiftData

/// Create/edit a `Snapshot`. When `existing` is nil we upsert — if the chosen
/// month already has a snapshot, the amount is updated in place (PRD §4.3.1).
struct SnapshotFormView: View {
    let holding: Holding
    let existing: Snapshot?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var periodMonth: Date
    @State private var amount: Decimal?

    init(holding: Holding, existing: Snapshot?) {
        self.holding = holding
        self.existing = existing
        _periodMonth = State(initialValue: existing?.periodMonth ?? Snapshot.normalize(.now))
        _amount = State(initialValue: existing?.amount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "snapshot.form.month",
                        selection: $periodMonth,
                        displayedComponents: [.date]
                    )
                    .disabled(existing != nil)
                } header: {
                    Text("snapshot.form.month")
                }
                Section {
                    LabeledContent {
                        TextField(
                            "snapshot.form.amount",
                            value: $amount,
                            format: .number
                        )
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                    } label: {
                        Text(verbatim: holding.currency)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(Color.notionInkSecondary)
                    }
                } header: {
                    Text("snapshot.form.amount")
                } footer: {
                    Text(verbatim: CurrencyCatalog.displayName(holding.currency))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .glassListStyle()
            .navigationTitle(existing == nil ? "snapshot.new.title" : "snapshot.edit.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("common.action.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text("common.action.save")
                    }
                    .disabled(amount == nil)
                }
            }
        }
    }

    @MainActor
    private func save() {
        guard let amount else { return }
        SnapshotService.upsert(
            amount: amount,
            periodMonth: periodMonth,
            for: holding,
            context: context
        )
        dismiss()
    }
}

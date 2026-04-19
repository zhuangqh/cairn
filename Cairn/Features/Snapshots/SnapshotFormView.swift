import SwiftUI
import SwiftData

/// Create/edit a `Snapshot`. When `existing` is nil we upsert — if the
/// chosen day already has a snapshot, the amount is updated in place
/// (PRD §4.3.1). Any calendar day can be picked; the stored value is
/// normalized to the start of that day in UTC.
struct SnapshotFormView: View {
    let holding: Holding
    let existing: Snapshot?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var periodDate: Date
    /// Amounts are stored as `Decimal` on the model, but the form only
    /// accepts non-negative whole numbers so the numeric keypad / input
    /// stays unambiguous across locales that use `.` vs `,` as the
    /// decimal separator. Kept as a `String` so we can filter non-digit
    /// keystrokes on macOS (where there is no `.numberPad` keyboard to
    /// constrain input at the OS level).
    @State private var amountText: String

    init(holding: Holding, existing: Snapshot?) {
        self.holding = holding
        self.existing = existing
        _periodDate = State(initialValue: existing?.periodMonth ?? Snapshot.normalizeDay(.now))
        let existingInt: Int? = existing.flatMap { Self.decimalToInt($0.amount) }
        _amountText = State(initialValue: existingInt.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "snapshot.form.date",
                        selection: $periodDate,
                        displayedComponents: [.date]
                    )
                    .disabled(existing != nil)
                } header: {
                    Text("snapshot.form.date")
                }
                Section {
                    LabeledContent {
                        TextField(
                            "snapshot.form.amount",
                            text: $amountText
                        )
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        #if !os(macOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: amountText) { _, newValue in
                            let filtered = newValue.filter(\.isASCII).filter(\.isNumber)
                            if filtered != newValue {
                                amountText = filtered
                            }
                        }
                    } label: {
                        Text(verbatim: holding.currency)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(Color.notionInkSecondary)
                    }
                } header: {
                    Text("snapshot.form.amount")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: CurrencyCatalog.displayName(holding.currency))
                        Text("snapshot.form.amount.hint")
                    }
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
                    .disabled(!isValid)
                }
            }
        }
    }

    // MARK: - Validation

    /// Parsed non-negative integer from the current input, or `nil` when
    /// the field is empty. Because `amountText` is filtered down to
    /// digits only, the value is always `>= 0` once parsed.
    private var parsedAmount: Int? {
        amountText.isEmpty ? nil : Int(amountText)
    }

    private var isValid: Bool { parsedAmount != nil }

    // MARK: - Actions

    @MainActor
    private func save() {
        guard let amount = parsedAmount else { return }
        SnapshotService.upsert(
            amount: Decimal(amount),
            periodMonth: periodDate,
            for: holding,
            context: context
        )
        dismiss()
    }

    /// Best-effort `Decimal -> Int` for prefilling the editor. Fractional
    /// values round to the nearest integer so legacy snapshots with
    /// cents still show a reasonable default.
    private static func decimalToInt(_ decimal: Decimal) -> Int? {
        var source = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

#Preview("SnapshotForm · new") {
    let env = PreviewSampleData.seededContainer()
    return SnapshotFormView(holding: env.seed.checkingUSD, existing: nil)
        .modelContainer(env.container)
}

#Preview("SnapshotForm · edit") {
    let env = PreviewSampleData.seededContainer()
    let latest = (env.seed.checkingUSD.snapshots ?? [])
        .sorted { $0.periodMonth > $1.periodMonth }
        .first
    return SnapshotFormView(holding: env.seed.checkingUSD, existing: latest)
        .modelContainer(env.container)
}

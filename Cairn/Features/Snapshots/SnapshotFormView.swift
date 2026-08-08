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
    @FocusState private var isAmountFocused: Bool

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
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        holdingCard
                        dateCard
                        amountCard
                    }
                    .pageHorizontalPadding()
                    .padding(.vertical, 20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(existing == nil ? "snapshot.new.title" : "snapshot.edit.title")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .keyboardDismissable(showsToolbar: false)
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
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    // MARK: - Cards

    private var holdingCard: some View {
        HStack(spacing: 12) {
            GlyphBadge(
                systemName: holding.account?.kind.iconName ?? "banknote.fill",
                tint: holding.account?.kind.tint ?? .accentColor,
                size: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: holding.account?.name.isEmpty == false ? holding.account!.name : holding.currency)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.notionInk)
                    .lineLimit(1)
                if let label = holding.label, !label.isEmpty {
                    Text(verbatim: "\(CurrencyCatalog.displayName(holding.currency)) · \(label)")
                        .font(.caption)
                        .foregroundStyle(Color.notionInkSecondary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: CurrencyCatalog.displayName(holding.currency))
                        .font(.caption)
                        .foregroundStyle(Color.notionInkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .glassCard(cornerRadius: 16, padding: 20)
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            NotionSectionHeader("snapshot.form.date", systemImage: "calendar")
            DatePicker(
                "snapshot.form.date",
                selection: $periodDate,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .disabled(existing != nil)
            .opacity(existing != nil ? 0.6 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 20)
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            NotionSectionHeader("snapshot.form.amount", systemImage: "banknote")

            HStack(spacing: 10) {
                Text(verbatim: holding.currency)
                    .font(.callout.weight(.semibold).monospaced())
                    .foregroundStyle(Color.notionInkMuted)

                Divider()
                    .frame(height: 22)

                TextField("snapshot.form.amount", text: $amountText)
                    .focused($isAmountFocused)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.notionInk)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: amountText) { _, newValue in
                        let filtered = newValue.filter(\.isASCII).filter(\.isNumber)
                        if filtered != newValue {
                            amountText = filtered
                        }
                    }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(amountFieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(amountFieldBorder, lineWidth: isAmountFocused ? 1.5 : 0.75)
            )
            .animation(.easeInOut(duration: 0.15), value: isAmountFocused)

            Text("snapshot.form.amount.hint")
                .font(.footnote)
                .foregroundStyle(Color.notionInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 20)
    }

    private var amountFieldBackground: Color {
        isAmountFocused ? Color.notionBlue.opacity(0.055) : Color.notionSurfaceAlt.opacity(0.72)
    }

    private var amountFieldBorder: Color {
        isAmountFocused ? Color.notionBlue.opacity(0.65) : Color.notionBorder
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

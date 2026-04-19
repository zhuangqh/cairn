import SwiftUI

/// One row in the `BatchEntryView` grouped list.
struct BatchEntryRowView: View {
    let accountName: String
    let accountKind: AccountKind
    let currency: String
    let label: String?
    let previousAmount: Decimal?
    let homeCurrency: String
    let convertedPreview: Decimal?
    let isDirty: Bool
    let isSaved: Bool
    @Binding var amount: Decimal?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            GlyphBadge(systemName: accountKind.iconName, tint: accountKind.tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: accountName)
                    .font(.body.weight(.medium))
                metaRow
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                TextField(
                    previousAmount.map { formatAmount($0) } ?? "",
                    value: $amount,
                    format: .number
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(minWidth: 120, maxWidth: 160)

                subtext
            }
            statusDot
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(verbatim: currency)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15), in: Capsule())
            if let label, !label.isEmpty {
                Text(verbatim: label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let previousAmount {
                Text(verbatim: previousHint(amount: previousAmount))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var subtext: some View {
        if let converted = convertedPreview {
            Text(converted, format: .currency(code: homeCurrency).locale(locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if amount != nil && currency != homeCurrency {
            Text("overview.missingRates.short")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(isDirty ? Color.yellow : (isSaved ? Color.green : Color.secondary.opacity(0.25)))
            .frame(width: 8, height: 8)
    }

    private func previousHint(amount: Decimal) -> String {
        let template = String(localized: "batch.previousHint")
        let formatted = amount.formatted(.currency(code: currency).locale(locale))
        return template.replacingOccurrences(of: "{amount}", with: formatted)
    }

    private func formatAmount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}

#Preview("BatchEntryRow · states") {
    struct Harness: View {
        @State private var dirtyAmount: Decimal? = 1_250
        @State private var pristineAmount: Decimal?
        @State private var savedAmount: Decimal? = 3_210
        @State private var missingFXAmount: Decimal? = 990

        var body: some View {
            List {
                BatchEntryRowView(
                    accountName: "Checking",
                    accountKind: .cash,
                    currency: "USD",
                    label: nil,
                    previousAmount: 1_200,
                    homeCurrency: "USD",
                    convertedPreview: 1_250,
                    isDirty: true,
                    isSaved: false,
                    amount: $dirtyAmount
                )
                BatchEntryRowView(
                    accountName: "Travel",
                    accountKind: .cash,
                    currency: "EUR",
                    label: "Euro wallet",
                    previousAmount: nil,
                    homeCurrency: "USD",
                    convertedPreview: nil,
                    isDirty: false,
                    isSaved: false,
                    amount: $pristineAmount
                )
                BatchEntryRowView(
                    accountName: "Brokerage",
                    accountKind: .stock,
                    currency: "USD",
                    label: "Index funds",
                    previousAmount: 3_000,
                    homeCurrency: "USD",
                    convertedPreview: 3_210,
                    isDirty: false,
                    isSaved: true,
                    amount: $savedAmount
                )
                BatchEntryRowView(
                    accountName: "Apartment",
                    accountKind: .realEstate,
                    currency: "JPY",
                    label: nil,
                    previousAmount: 980,
                    homeCurrency: "USD",
                    convertedPreview: nil,
                    isDirty: true,
                    isSaved: false,
                    amount: $missingFXAmount
                )
            }
        }
    }
    return Harness()
}

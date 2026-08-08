import SwiftUI

/// One row in the `BatchEntryView` grouped list.
///
/// Apple-Stocks / Wallet-inspired layout:
///   - Left: glyph badge, account name, small currency label.
///   - Right: large bold current value (no currency symbol),
///            colored delta vs. previous (`+12,340 (+6.5%) ↑`),
///            subtle home-currency conversion (`≈ ¥1,387,127`).
/// The previous value itself is intentionally hidden from the main
/// layout and surfaced only via a `.help` tooltip / accessibility hint.
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
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            GlyphBadge(systemName: accountKind.iconName, tint: accountKind.tint, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: accountName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                metaRow
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 3) {
                amountField
                deltaLine
                convertedLine
            }

            statusIndicator
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .help(tooltipText)
        .accessibilityHint(Text(tooltipText))
    }

    // MARK: - Subviews

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(verbatim: currency)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            if let label, !label.isEmpty {
                Text(verbatim: "·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(verbatim: label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var amountField: some View {
        HStack(spacing: 8) {
            Text(verbatim: currency)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(Color.notionInkMuted)

            Divider()
                .frame(height: 17)

            TextField(
                placeholderText,
                value: $amount,
                format: .number.precision(.fractionLength(0...2))
            )
            .focused($isFieldFocused)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.body.weight(.semibold).monospacedDigit())
            .foregroundStyle(Color.notionInk)
            #if !os(macOS)
            .keyboardType(.decimalPad)
            #endif
        }
        .frame(minWidth: 150, maxWidth: 210)
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(fieldBorder, lineWidth: isFieldFocused ? 1.5 : 0.75)
        )
        .animation(.easeInOut(duration: 0.15), value: isFieldFocused)
    }

    @ViewBuilder
    private var deltaLine: some View {
        if let info = deltaInfo {
            HStack(spacing: 4) {
                Image(systemName: info.iconName)
                    .font(.caption2.weight(.bold))
                Text(verbatim: info.absoluteText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                if !info.percentText.isEmpty {
                    Text(verbatim: info.percentText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(info.color.opacity(0.85))
                }
            }
            .foregroundStyle(info.color)
        } else if amount != nil, previousAmount == nil {
            // First-time entry — gentle hint, no comparison.
            Text("batch.row.firstEntry")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var convertedLine: some View {
        if let converted = convertedPreview, currency != homeCurrency {
            Text(verbatim: "≈ " + converted.formatted(.currency(code: homeCurrency).locale(locale)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        } else if amount != nil, currency != homeCurrency, convertedPreview == nil {
            Text("assets.missingRates.short")
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.8))
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isDirty {
            Circle()
                .fill(Color.notionBlue)
                .frame(width: 7, height: 7)
                .accessibilityLabel(Text("batch.row.edited"))
        } else if isSaved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.notionGreen)
                .accessibilityHidden(true)
        } else {
            Circle()
                .strokeBorder(Color.notionBorder, lineWidth: 1)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Derived

    private struct DeltaInfo {
        let absoluteText: String
        let percentText: String
        let iconName: String
        let color: Color
    }

    private var deltaInfo: DeltaInfo? {
        guard let current = amount, let previous = previousAmount else { return nil }
        let delta = current - previous
        if delta == 0 { return nil }

        // Absolute change with explicit sign, no currency symbol.
        let absText = delta.formatted(
            .number.sign(strategy: .always(includingZero: false))
                .precision(.fractionLength(0...2))
                .locale(locale)
        )

        // Percent change — guard against zero baseline.
        let percentText: String
        if previous != 0 {
            let pct = NSDecimalNumber(decimal: delta / previous).doubleValue
            percentText = "(" + pct.formatted(
                .percent.sign(strategy: .always(includingZero: false))
                    .precision(.fractionLength(1))
                    .locale(locale)
            ) + ")"
        } else {
            percentText = ""
        }

        let isUp = delta > 0
        return DeltaInfo(
            absoluteText: absText,
            percentText: percentText,
            iconName: isUp ? "arrow.up" : "arrow.down",
            color: isUp ? .green : .red
        )
    }

    private var fieldBackground: Color {
        if isFieldFocused { return Color.notionBlue.opacity(0.055) }
        return Color.notionSurfaceAlt.opacity(0.72)
    }

    private var fieldBorder: Color {
        if isFieldFocused { return Color.notionBlue.opacity(0.65) }
        if isDirty { return Color.notionBlue.opacity(0.24) }
        return Color.notionBorder
    }

    private var placeholderText: String {
        previousAmount.map { formatPlain($0) } ?? "—"
    }

    private var tooltipText: String {
        guard let previous = previousAmount else {
            return String(localized: "batch.row.firstEntry")
        }
        let template = String(localized: "batch.previousHint")
        let formatted = previous.formatted(.currency(code: currency).locale(locale))
        return template.replacingOccurrences(of: "{amount}", with: formatted)
    }

    private func formatPlain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}

#Preview("BatchEntryRow · states") {
    struct Harness: View {
        @State private var increased: Decimal? = 1_399_467
        @State private var decreased: Decimal? = 2_840
        @State private var unchanged: Decimal? = 3_210
        @State private var firstTime: Decimal? = 5_000
        @State private var blank: Decimal?
        @State private var missingFX: Decimal? = 980_000

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    BatchEntryRowView(
                        accountName: "US Stocks",
                        accountKind: .stock,
                        currency: "USD",
                        label: "Brokerage",
                        previousAmount: 1_312_500,
                        homeCurrency: "CNY",
                        convertedPreview: 10_125_440,
                        isDirty: true,
                        isSaved: false,
                        amount: $increased
                    )
                    Divider().opacity(0.4)
                    BatchEntryRowView(
                        accountName: "AUD Cash",
                        accountKind: .cash,
                        currency: "AUD",
                        label: nil,
                        previousAmount: 3_120,
                        homeCurrency: "CNY",
                        convertedPreview: 13_870,
                        isDirty: true,
                        isSaved: false,
                        amount: $decreased
                    )
                    Divider().opacity(0.4)
                    BatchEntryRowView(
                        accountName: "CNY Cash",
                        accountKind: .cash,
                        currency: "CNY",
                        label: "Savings",
                        previousAmount: 3_210,
                        homeCurrency: "CNY",
                        convertedPreview: nil,
                        isDirty: false,
                        isSaved: true,
                        amount: $unchanged
                    )
                    Divider().opacity(0.4)
                    BatchEntryRowView(
                        accountName: "A-Shares",
                        accountKind: .stock,
                        currency: "CNY",
                        label: nil,
                        previousAmount: nil,
                        homeCurrency: "CNY",
                        convertedPreview: nil,
                        isDirty: true,
                        isSaved: false,
                        amount: $firstTime
                    )
                    Divider().opacity(0.4)
                    BatchEntryRowView(
                        accountName: "Travel Wallet",
                        accountKind: .cash,
                        currency: "EUR",
                        label: nil,
                        previousAmount: 2_400,
                        homeCurrency: "CNY",
                        convertedPreview: nil,
                        isDirty: false,
                        isSaved: false,
                        amount: $blank
                    )
                    Divider().opacity(0.4)
                    BatchEntryRowView(
                        accountName: "JPY Apartment",
                        accountKind: .realEstate,
                        currency: "JPY",
                        label: nil,
                        previousAmount: 970_000,
                        homeCurrency: "CNY",
                        convertedPreview: nil,
                        isDirty: true,
                        isSaved: false,
                        amount: $missingFX
                    )
                }
                .padding(.horizontal, 16)
            }
        }
    }
    return Harness()
}

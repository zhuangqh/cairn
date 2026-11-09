import SwiftUI

/// Possessions total: eyebrow, purchase-cost headline, item count, and a
/// missing-rates warning. Full size it mirrors the Financial hero; `compact`
/// is the showcase nameplate with the count beside a smaller total.
struct PossessionsTotalSummary: View {
    let total: Decimal
    let homeCurrency: String
    let activeCount: Int
    let missingCurrencies: [String]
    let compact: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            HStack(spacing: 6) {
                Text("possession.total.title")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: homeCurrency)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(
                    total,
                    format: .currency(code: homeCurrency)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                    .font(compact ? .system(.title, design: .rounded, weight: .bold)
                          : .system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Color.notionInk)
                if compact {
                    Text(possessionCountFootnote(activeCount: activeCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !missingCurrencies.isEmpty {
                Label {
                    Text(missingRatesMessage(missingCurrencies))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                .font(.footnote)
                .padding(.top, 4)
            }
            if !compact {
                Text(possessionCountFootnote(activeCount: activeCount))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private func possessionCountFootnote(activeCount: Int) -> String {
        let template = String(localized: "possession.count.active")
        return template.replacingOccurrences(of: "{count}", with: String(activeCount))
    }

    private func missingRatesMessage(_ currencies: [String]) -> String {
        let list = currencies.joined(separator: ", ")
        let template = String(localized: "assets.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }
}

import SwiftUI

/// "By currency" card: one row per currency the household holds, valued in
/// the home currency, with the native balance as a caption for foreign
/// currencies. Mirrors the By member card's layout.
struct AssetsCurrencyCard: View {
    let totals: [NetWorthCalculator.CurrencyTotal]
    /// Household total in `homeCurrency`; denominator for share bars.
    let householdTotal: Decimal
    /// Month-over-month percentage deltas keyed by currency code.
    let monthDeltas: [String: Double]
    let homeCurrency: String
    let locale: Locale

    var body: some View {
        AssetsBreakdownCard(titleKey: "assets.byCurrency") {
            ForEach(Array(totals.enumerated()), id: \.element.id) { index, entry in
                AssetsCurrencyRow(
                    total: entry,
                    share: share(of: entry),
                    monthDelta: monthDeltas[entry.currency],
                    homeCurrency: homeCurrency,
                    locale: locale
                )
                if index < totals.count - 1 {
                    Divider().opacity(0.35)
                }
            }
        }
    }

    /// `nil` for negative or unconverted totals, which render as "—".
    private func share(of entry: NetWorthCalculator.CurrencyTotal) -> Double? {
        guard let converted = entry.convertedAmount, converted >= 0, householdTotal > 0 else { return nil }
        let value = NSDecimalNumber(decimal: converted / householdTotal).doubleValue
        return min(1, value)
    }
}

private struct AssetsCurrencyRow: View {
    let total: NetWorthCalculator.CurrencyTotal
    let share: Double?
    let monthDelta: Double?
    let homeCurrency: String
    let locale: Locale

    var body: some View {
        AssetsBreakdownRow(
            leading: { CurrencyCodeBadge(code: total.currency) },
            title: CurrencyCatalog.displayName(total.currency, in: locale),
            caption: nativeCaption,
            trailing: { trailing },
            share: share,
            showsShare: total.convertedAmount != nil,
            monthDelta: monthDelta,
            currencyCode: homeCurrency,
            locale: locale
        )
    }

    @ViewBuilder
    private var trailing: some View {
        if let converted = total.convertedAmount {
            AssetsBreakdownAmount(amount: converted, currencyCode: homeCurrency, locale: locale)
        } else {
            Label {
                Text("assets.byCurrency.missingRate")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
    }

    /// Native balance, omitted for the home currency where it would repeat
    /// the trailing amount.
    private var nativeCaption: String? {
        guard total.currency != homeCurrency || total.convertedAmount == nil else { return nil }
        return total.nativeAmount.formatted(
            .currency(code: total.currency)
                .locale(locale)
                .precision(.fractionLength(0))
        )
    }
}

/// 32pt circular mark that fills the avatar slot of breakdown rows: the
/// issuing region's flag, or the currency code when no flag applies.
private struct CurrencyCodeBadge: View {
    let code: String

    var body: some View {
        Group {
            if let flag = CurrencyCatalog.flagEmoji(for: code) {
                // Oversized glyph, kept at its natural size and centered, then
                // clipped to the circle so the flag fills it edge to edge; the
                // hairline keeps pale flags defined.
                Text(verbatim: flag)
                    .font(.system(size: 56))
                    .fixedSize()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            } else {
                codeMark
            }
        }
        .accessibilityHidden(true)
    }

    private var codeMark: some View {
        Text(verbatim: code)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }
}

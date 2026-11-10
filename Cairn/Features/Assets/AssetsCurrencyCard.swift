import SwiftUI

/// "By currency" section: one progress row per currency the household holds,
/// valued in the home currency, with the native balance as an inline caption
/// for foreign currencies. Shares the By member section's columns.
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
            ForEach(totals) { entry in
                AssetsCurrencyRow(
                    total: entry,
                    share: share(of: entry),
                    monthDelta: monthDeltas[entry.currency],
                    homeCurrency: homeCurrency,
                    locale: locale
                )
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
            leading: { CurrencyCodeTag(code: total.currency) },
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
            .foregroundStyle(Color.red)
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

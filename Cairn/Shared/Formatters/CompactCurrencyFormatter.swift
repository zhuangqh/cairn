import Foundation

/// Compact, locale-aware currency formatter used by the Dashboard's
/// hero / composition / allocation surfaces.
///
/// The dashboard repeats large home-currency figures many times in a single
/// glance. Rendering each one as a fully-qualified currency string (e.g.
/// `CN¥ 4,567,890`) drowns the layout in punctuation and currency codes.
/// This helper produces a short form (`¥4.57M`, `$213.1K`) using the locale's
/// own currency symbol while keeping the sign-aware behaviour the deltas
/// need.
@MainActor
enum CompactCurrencyFormatter {

    /// Returns a short, abbreviated representation of `amount` using the
    /// locale's currency symbol for `code`.
    ///
    /// - Parameters:
    ///   - amount: Value to format.
    ///   - code: ISO 4217 currency code (e.g. `"CNY"`, `"USD"`).
    ///   - locale: Locale that supplies the currency symbol + grouping.
    ///   - alwaysSigned: When `true`, positive values are prefixed with `+`.
    static func string(
        amount: Decimal,
        code: String,
        locale: Locale,
        alwaysSigned: Bool = false
    ) -> String {
        let symbol = currencySymbol(code: code, locale: locale)
        let value = NSDecimalNumber(decimal: amount).doubleValue
        let absValue = abs(value)

        let signPrefix: String
        if value < 0 { signPrefix = "−" }
        else if alwaysSigned && value > 0 { signPrefix = "+" }
        else { signPrefix = "" }

        let body: String
        switch absValue {
        case 1_000_000_000...:
            body = formatScaled(absValue / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            body = formatScaled(absValue / 1_000_000, suffix: "M")
        case 10_000...:
            body = formatScaled(absValue / 1_000, suffix: "K")
        case 1_000...:
            // Keep four-digit values readable without abbreviation.
            body = absValue.formatted(.number.precision(.fractionLength(0)).locale(locale))
        default:
            body = absValue.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }

        return "\(signPrefix)\(symbol)\(body)"
    }

    /// Compact format with a custom sign prefix override (used to render
    /// the delta line where we want `↑` / `↓` chevrons separately).
    static func unsignedString(
        amount: Decimal,
        code: String,
        locale: Locale
    ) -> String {
        string(amount: abs(amount), code: code, locale: locale, alwaysSigned: false)
    }

    private static func formatScaled(_ value: Double, suffix: String) -> String {
        // 1 fractional digit for tens / hundreds, 2 for single digits, 0
        // when the abbreviation would otherwise repeat the same digit
        // (`1.0M` -> `1M`).
        let digits: Int
        switch value {
        case 100...: digits = 0
        case 10...:  digits = 1
        default:     digits = 2
        }
        let formatted = value.formatted(.number.precision(.fractionLength(0...digits)))
        return "\(formatted)\(suffix)"
    }

    private static func currencySymbol(code: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        return formatter.currencySymbol ?? code
    }
}

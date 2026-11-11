import Foundation

/// Reuses one `.currency` `NumberFormatter` per (currency code, locale)
/// instead of allocating a new one on every render. Callers only read
/// derived properties (symbol, pattern, minor units), so a shared
/// instance returns exactly what a fresh one would. Keyed by the full
/// `Locale` value rather than its identifier, so a system locale with
/// custom preferences never shares an entry with a plain identifier
/// override from `LocalizationService`.
@MainActor
enum CurrencyFormatterCache {
    private struct Key: Hashable {
        let code: String
        let locale: Locale
    }

    private static var formatters: [Key: NumberFormatter] = [:]

    static func formatter(code: String, locale: Locale) -> NumberFormatter {
        let key = Key(code: code, locale: locale)
        if let cached = formatters[key] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        formatters[key] = formatter
        return formatter
    }
}

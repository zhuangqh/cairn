import Foundation

/// Static catalog of ISO 4217 currency codes with a small, hand-picked
/// "frequently used" set pinned at the top (see PRD §4.2 F-ACC-2).
public enum CurrencyCatalog {
    /// Codes that most users will pick; ordered by expected frequency for
    /// the app's target audience.
    public static let pinned: [String] = [
        "CNY", "USD", "HKD", "AUD", "EUR", "JPY", "GBP", "SGD", "CAD", "NZD"
    ]

    /// Full set, sorted alphabetically. Pinned codes are deduped from this list
    /// in `allSorted` so the UI can render a clear two-section picker.
    public static let all: [String] = Locale.commonISOCurrencyCodes

    /// Non-pinned codes, alphabetically.
    public static var rest: [String] {
        let pinnedSet = Set(pinned)
        return all.filter { !pinnedSet.contains($0) }.sorted()
    }

    /// Localized display name for a currency code under the current locale.
    public static func displayName(_ code: String, in locale: Locale = .current) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }
}

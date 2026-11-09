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

    /// Flag emoji of the issuing region. ISO 4217 codes start with the
    /// issuer's ISO 3166 region code (USD → US, EUR → EU). Returns `nil` for
    /// supranational or commodity codes (`X…`) and prefixes that are not a
    /// current region, so callers can fall back to showing the code.
    public static func flagEmoji(for code: String) -> String? {
        let upper = code.uppercased()
        guard upper.count == 3, !upper.hasPrefix("X") else { return nil }
        let region = String(upper.prefix(2))
        guard region == "EU" || flagRegions.contains(region) else { return nil }
        let regionalIndicatorOffset: UInt32 = 0x1F1E6 - 0x41
        let scalars = region.unicodeScalars.compactMap { Unicode.Scalar($0.value + regionalIndicatorOffset) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static let flagRegions: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier))
}

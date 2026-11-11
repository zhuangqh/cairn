import Foundation

/// The "no exchange rate for …" footnote shown under totals that skip
/// currencies without a usable rate.
enum MissingRatesMessage {
    /// `assets.missingRates` with `{currencies}` replaced by the
    /// comma-separated currency codes.
    static func text(for currencies: [String]) -> String {
        let list = currencies.joined(separator: ", ")
        let template = String(localized: "assets.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: list)
    }
}

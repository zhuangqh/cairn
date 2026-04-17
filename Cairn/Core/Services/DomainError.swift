import Foundation

/// Errors raised by the app's service layer when a user action would violate a
/// business invariant. Each case carries a localization key so the UI can
/// render a helpful message via the String Catalog.
public enum DomainError: LocalizedError, Equatable {
    /// A Holding with the same currency already exists in the target Account.
    case duplicateCurrencyInAccount(currency: String)

    /// Attempted to change a Holding's currency after creation.
    case holdingCurrencyIsImmutable

    /// Required field left blank.
    case missingRequiredField(fieldKey: String)

    public var localizationKey: String {
        switch self {
        case .duplicateCurrencyInAccount: return "error.holding.duplicateCurrency"
        case .holdingCurrencyIsImmutable: return "error.holding.currencyImmutable"
        case .missingRequiredField: return "error.field.required"
        }
    }

    public var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

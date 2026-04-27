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

    /// Backup payload could not be decoded as a Cairn backup at all
    /// (corrupt JSON, wrong file, missing required fields).
    case backupUnreadable

    /// Backup payload was produced by a newer version of Cairn that this
    /// build does not understand. The user should upgrade the app.
    case backupTooNew(fileVersion: Int, supportedVersion: Int)

    /// Restore failed while writing data back to the local store. The
    /// store has been rolled back to its prior state.
    case backupWriteFailed

    public var localizationKey: String {
        switch self {
        case .duplicateCurrencyInAccount: return "error.holding.duplicateCurrency"
        case .holdingCurrencyIsImmutable: return "error.holding.currencyImmutable"
        case .missingRequiredField: return "error.field.required"
        case .backupUnreadable: return "settings.backup.import.failure.unreadable"
        case .backupTooNew: return "settings.backup.import.failure.tooNew"
        case .backupWriteFailed: return "settings.backup.import.failure.write"
        }
    }

    public var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

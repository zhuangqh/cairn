import Foundation
import SwiftData

/// Business rules for `Holding` that can't be expressed in the SwiftData model
/// (because CloudKit sync forbids `@Attribute(.unique)`).
public enum HoldingService {
    /// Creates and inserts a new Holding in the given context, enforcing that
    /// its `currency` is unique within the target Account.
    @MainActor
    @discardableResult
    public static func create(
        currency: String,
        label: String? = nil,
        in account: Account,
        context: ModelContext
    ) throws -> Holding {
        try assertCurrencyIsAvailable(currency, in: account)
        let holding = Holding(currency: currency, label: label, account: account)
        context.insert(holding)
        return holding
    }

    /// Throws `.duplicateCurrencyInAccount` if `account` already has an active
    /// (non-archived) Holding with `currency`.
    @MainActor
    public static func assertCurrencyIsAvailable(
        _ currency: String,
        in account: Account
    ) throws {
        let existing = (account.holdings ?? []).contains {
            !$0.isArchived && $0.currency == currency
        }
        if existing {
            throw DomainError.duplicateCurrencyInAccount(currency: currency)
        }
    }
}

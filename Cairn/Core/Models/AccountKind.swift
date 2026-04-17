import Foundation

/// Stable persistence tokens for account kinds.
///
/// Raw values are written to the store and MUST NOT be changed without a migration.
/// User-facing labels come from the String Catalog (`account.kind.*`).
public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case cash
    case stock
    case realEstate
    case device

    /// Localization key for the user-facing name of the kind.
    public var localizationKey: String {
        switch self {
        case .cash: return "account.kind.cash"
        case .stock: return "account.kind.stock"
        case .realEstate: return "account.kind.realEstate"
        case .device: return "account.kind.device"
        }
    }
}

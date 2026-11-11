import Foundation
import SwiftData

/// A physical possession owned by a family `Member` (PRD §4.7, v1.1):
/// real estate, vehicles, electronics, etc. Valued manually — there is no
/// per-month `Snapshot` series. The current value defaults to `purchasePrice`
/// until the user overrides it via `currentValue`.
///
/// Sold possessions carry a `saleDate` + `salePrice` and are excluded from current
/// net worth but retained in history.
///
/// Note: CloudKit-backed SwiftData requires every stored property to have a
/// default value and every to-many relationship to be an optional array.
@Model
final class Possession {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRawValue: String = PossessionCategory.realEstate.rawValue

    /// Native acquisition price in `purchaseCurrency`.
    var purchasePrice: Decimal = 0
    var purchaseCurrency: String = "USD"
    var purchaseDate: Date = Date()

    /// Manual revaluation in `purchaseCurrency`. When `nil`, callers should
    /// fall back to `purchasePrice` for "current value" reporting.
    var currentValue: Decimal?
    var currentValueUpdatedAt: Date?

    /// Non-nil marks the possession as disposed of.
    var saleDate: Date?
    var salePrice: Decimal?

    /// Optional custom SF Symbol override (reserved for a future icon library).
    var iconName: String?
    /// User photo shown in the Possessions showcase: an on-device subject
    /// cutout (transparent PNG), or the downscaled original when no subject
    /// was found. Kept out of the store file by external storage.
    @Attribute(.externalStorage) var photoData: Data?
    var note: String?
    var createdAt: Date = Date()

    @Relationship var member: Member?

    /// Typed accessor over the persisted `categoryRawValue` token.
    var category: PossessionCategory {
        get { PossessionCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    /// Whether the possession has been disposed of (i.e. has a sale date).
    var isSold: Bool { saleDate != nil }

    /// Effective value for "what it's worth today" reporting.
    /// Falls back to `purchasePrice` when no manual revaluation has been made.
    /// Returns `nil` for sold possessions (they are excluded from current net worth).
    var effectiveValue: Decimal? {
        guard !isSold else { return nil }
        return currentValue ?? purchasePrice
    }

    init(
        name: String,
        category: PossessionCategory,
        purchasePrice: Decimal,
        purchaseCurrency: String,
        purchaseDate: Date = .now,
        currentValue: Decimal? = nil,
        currentValueUpdatedAt: Date? = nil,
        saleDate: Date? = nil,
        salePrice: Decimal? = nil,
        iconName: String? = nil,
        photoData: Data? = nil,
        note: String? = nil,
        member: Member? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRawValue = category.rawValue
        self.purchasePrice = purchasePrice
        self.purchaseCurrency = purchaseCurrency
        self.purchaseDate = purchaseDate
        self.currentValue = currentValue
        self.currentValueUpdatedAt = currentValueUpdatedAt
        self.saleDate = saleDate
        self.salePrice = salePrice
        self.iconName = iconName
        self.photoData = photoData
        self.note = note
        self.member = member
        self.createdAt = createdAt
    }
}

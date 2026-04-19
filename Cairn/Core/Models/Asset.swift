import Foundation
import SwiftData

/// A physical asset owned by a family `Member` (PRD §4.7, v1.1):
/// real estate, vehicles, electronics, etc. Valued manually — there is no
/// per-month `Snapshot` series. The current value defaults to `purchasePrice`
/// until the user overrides it via `currentValue`.
///
/// Sold assets carry a `saleDate` + `salePrice` and are excluded from current
/// net worth but retained in history.
///
/// Note: CloudKit-backed SwiftData requires every stored property to have a
/// default value and every to-many relationship to be an optional array.
@Model
public final class Asset {
    public var id: UUID = UUID()
    public var name: String = ""
    public var categoryRawValue: String = AssetCategory.realEstate.rawValue

    /// Native acquisition price in `purchaseCurrency`.
    public var purchasePrice: Decimal = 0
    public var purchaseCurrency: String = "USD"
    public var purchaseDate: Date = Date()

    /// Manual revaluation in `purchaseCurrency`. When `nil`, callers should
    /// fall back to `purchasePrice` for "current value" reporting.
    public var currentValue: Decimal?
    public var currentValueUpdatedAt: Date?

    /// Non-nil marks the asset as disposed of.
    public var saleDate: Date?
    public var salePrice: Decimal?

    /// Optional custom SF Symbol override (reserved for a future icon library).
    public var iconName: String?
    public var note: String?
    public var createdAt: Date = Date()

    @Relationship public var member: Member?

    /// Typed accessor over the persisted `categoryRawValue` token.
    public var category: AssetCategory {
        get { AssetCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    /// Whether the asset has been disposed of (i.e. has a sale date).
    public var isSold: Bool { saleDate != nil }

    /// Effective value for "what it's worth today" reporting.
    /// Falls back to `purchasePrice` when no manual revaluation has been made.
    /// Returns `nil` for sold assets (they are excluded from current net worth).
    public var effectiveValue: Decimal? {
        guard !isSold else { return nil }
        return currentValue ?? purchasePrice
    }

    public init(
        name: String,
        category: AssetCategory,
        purchasePrice: Decimal,
        purchaseCurrency: String,
        purchaseDate: Date = .now,
        currentValue: Decimal? = nil,
        currentValueUpdatedAt: Date? = nil,
        saleDate: Date? = nil,
        salePrice: Decimal? = nil,
        iconName: String? = nil,
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
        self.note = note
        self.member = member
        self.createdAt = createdAt
    }
}

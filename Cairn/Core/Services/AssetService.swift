import Foundation
import SwiftData

/// CRUD + aggregation helpers for physical `Asset` records (PRD §4.7, v1.1).
///
/// Unlike `Holding`, an `Asset` has no monthly `Snapshot` series. Its
/// "current" valuation is `currentValue ?? purchasePrice`, and sold assets
/// (`saleDate != nil`) are excluded from current-value reporting.
@MainActor
public enum AssetService {

    public struct CategoryTotal: Sendable, Equatable, Identifiable {
        public let category: AssetCategory
        public let amount: Decimal
        public var id: AssetCategory { category }
    }

    public struct Totals: Sendable, Equatable {
        public var amount: Decimal
        /// Purchase currencies encountered that could not be converted to the
        /// home currency. UI should prompt for an FX rate refresh.
        public var missingCurrencies: [String]
    }

    // MARK: - CRUD

    @discardableResult
    public static func create(
        name: String,
        category: AssetCategory,
        purchasePrice: Decimal,
        purchaseCurrency: String,
        purchaseDate: Date,
        member: Member,
        note: String? = nil,
        context: ModelContext
    ) throws -> Asset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainError.missingRequiredField(fieldKey: "asset.form.name")
        }
        let asset = Asset(
            name: trimmed,
            category: category,
            purchasePrice: purchasePrice,
            purchaseCurrency: purchaseCurrency,
            purchaseDate: purchaseDate,
            note: note,
            member: member
        )
        context.insert(asset)
        return asset
    }

    /// Stamp a new manual valuation in the asset's native currency.
    public static func updateCurrentValue(
        _ asset: Asset,
        to value: Decimal?,
        at timestamp: Date = .now
    ) {
        asset.currentValue = value
        asset.currentValueUpdatedAt = value == nil ? nil : timestamp
    }

    /// Mark an asset as sold. Pass `nil` values to clear the sale state.
    public static func markSold(
        _ asset: Asset,
        on date: Date?,
        price: Decimal?
    ) {
        asset.saleDate = date
        asset.salePrice = price
    }

    // MARK: - Aggregation

    /// Sum of every non-sold asset's effective value, converted to the home
    /// currency. Assets whose purchase currency has no FX rate are reported
    /// in `missingCurrencies`.
    ///
    /// When `asOf` is non-nil the total time-travels: only assets purchased
    /// on or before that date are included, sold assets whose sale happened
    /// on or before that date are excluded, and each asset is valued at its
    /// `purchasePrice` (historical manual valuations are not stored per
    /// month, so purchase price is the best available proxy). Passing `nil`
    /// preserves the "today" semantics used everywhere else.
    public static func total(
        homeCurrency: String,
        asOf: Date? = nil,
        context: ModelContext
    ) -> Totals {
        let assets = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        return aggregate(assets: assets, homeCurrency: homeCurrency, asOf: asOf, context: context)
    }

    /// Per-category totals, sorted by amount descending. See `total(...)`
    /// for the time-travel semantics when `asOf` is provided.
    public static func totalsByCategory(
        homeCurrency: String,
        asOf: Date? = nil,
        context: ModelContext
    ) -> [CategoryTotal] {
        let assets = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        var sums: [AssetCategory: Decimal] = [:]
        for asset in assets {
            guard let value = effectiveValue(for: asset, asOf: asOf) else { continue }
            let converted: Decimal?
            if asset.purchaseCurrency == homeCurrency {
                converted = value
            } else {
                converted = FXService.convert(
                    amount: value,
                    from: asset.purchaseCurrency,
                    to: homeCurrency,
                    in: context
                )
            }
            guard let v = converted else { continue }
            sums[asset.category, default: 0] += v
        }
        return sums
            .map { CategoryTotal(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    private static func aggregate(
        assets: [Asset],
        homeCurrency: String,
        asOf: Date?,
        context: ModelContext
    ) -> Totals {
        var total: Decimal = 0
        var missing: Set<String> = []
        for asset in assets {
            guard let value = effectiveValue(for: asset, asOf: asOf) else { continue }
            if asset.purchaseCurrency == homeCurrency {
                total += value
            } else if let converted = FXService.convert(
                amount: value,
                from: asset.purchaseCurrency,
                to: homeCurrency,
                in: context
            ) {
                total += converted
            } else {
                missing.insert(asset.purchaseCurrency)
            }
        }
        return Totals(amount: total, missingCurrencies: missing.sorted())
    }

    /// Returns the value an asset should contribute at a given cutoff.
    /// Current (asOf == nil): asset's `effectiveValue` unless sold.
    /// Historical (asOf != nil): purchase price for assets purchased by the
    /// cutoff and not sold before or on it; `nil` otherwise.
    private static func effectiveValue(for asset: Asset, asOf: Date?) -> Decimal? {
        guard let asOf else { return asset.effectiveValue }
        guard asset.purchaseDate <= asOf else { return nil }
        if let saleDate = asset.saleDate, saleDate <= asOf { return nil }
        return asset.purchasePrice
    }
}

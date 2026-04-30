import Foundation
import SwiftData

/// CRUD + aggregation helpers for physical `Possession` records (PRD §4.7, v1.1).
///
/// Unlike `Holding`, an `Possession` has no monthly `Snapshot` series. Its
/// "current" valuation is `currentValue ?? purchasePrice`, and sold possessions
/// (`saleDate != nil`) are excluded from current-value reporting.
@MainActor
public enum PossessionService {

    public struct CategoryTotal: Sendable, Equatable, Identifiable {
        public let category: PossessionCategory
        public let amount: Decimal
        public var id: PossessionCategory { category }
    }

    public struct Totals: Sendable, Equatable {
        public var amount: Decimal
        /// Purchase currencies encountered that could not be converted to the
        /// home currency. UI should prompt for an FX rate refresh.
        public var missingCurrencies: [String]
    }

    /// Bundle of every aggregate the Possessions / Dashboard screens need from
    /// one fetch + one FX cache pass — total in home currency, per-category
    /// breakdown, and the missing-currency warning list.
    public struct Bundle: Sendable, Equatable {
        public var totals: Totals
        public var byCategory: [CategoryTotal]
    }

    // MARK: - CRUD

    @discardableResult
    public static func create(
        name: String,
        category: PossessionCategory,
        purchasePrice: Decimal,
        purchaseCurrency: String,
        purchaseDate: Date,
        member: Member,
        note: String? = nil,
        context: ModelContext
    ) throws -> Possession {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainError.missingRequiredField(fieldKey: "possession.form.name")
        }
        let possession = Possession(
            name: trimmed,
            category: category,
            purchasePrice: purchasePrice,
            purchaseCurrency: purchaseCurrency,
            purchaseDate: purchaseDate,
            note: note,
            member: member
        )
        context.insert(possession)
        return possession
    }

    /// Stamp a new manual valuation in the possession's native currency.
    public static func updateCurrentValue(
        _ possession: Possession,
        to value: Decimal?,
        at timestamp: Date = .now
    ) {
        possession.currentValue = value
        possession.currentValueUpdatedAt = value == nil ? nil : timestamp
    }

    /// Mark an possession as sold. Pass `nil` values to clear the sale state.
    public static func markSold(
        _ possession: Possession,
        on date: Date?,
        price: Decimal?
    ) {
        possession.saleDate = date
        possession.salePrice = price
    }

    // MARK: - Aggregation

    /// Sum of every non-sold possession's effective value, converted to the home
    /// currency. Possessions whose purchase currency has no FX rate are reported
    /// in `missingCurrencies`.
    ///
    /// When `asOf` is non-nil the total time-travels: only possessions purchased
    /// on or before that date are included, sold possessions whose sale happened
    /// on or before that date are excluded, and each possession is valued at its
    /// `purchasePrice` (historical manual valuations are not stored per
    /// month, so purchase price is the best available proxy). Passing `nil`
    /// preserves the "today" semantics used everywhere else.
    public static func total(
        homeCurrency: String,
        asOf: Date? = nil,
        context: ModelContext
    ) -> Totals {
        let possessions = (try? context.fetch(FetchDescriptor<Possession>())) ?? []
        let cache = FXService.RateCache.load(in: context)
        return aggregate(possessions: possessions, homeCurrency: homeCurrency, asOf: asOf, cache: cache)
    }

    /// Per-category totals, sorted by amount descending. See `total(...)`
    /// for the time-travel semantics when `asOf` is provided.
    public static func totalsByCategory(
        homeCurrency: String,
        asOf: Date? = nil,
        context: ModelContext
    ) -> [CategoryTotal] {
        let possessions = (try? context.fetch(FetchDescriptor<Possession>())) ?? []
        let cache = FXService.RateCache.load(in: context)
        return categoryTotals(
            possessions: possessions,
            homeCurrency: homeCurrency,
            asOf: asOf,
            cache: cache
        )
    }

    /// Single-pass bundle. Useful when a view needs both the headline total
    /// and the per-category breakdown in the same render — avoids fetching
    /// `Possession` rows + the FX cache twice.
    public static func bundle(
        homeCurrency: String,
        asOf: Date? = nil,
        rateCache: FXService.RateCache? = nil,
        context: ModelContext
    ) -> Bundle {
        let possessions = (try? context.fetch(FetchDescriptor<Possession>())) ?? []
        let cache = rateCache ?? FXService.RateCache.load(in: context)
        var total: Decimal = 0
        var missing: Set<String> = []
        var sums: [PossessionCategory: Decimal] = [:]
        for possession in possessions {
            guard let value = effectiveValue(for: possession, asOf: asOf) else { continue }
            let converted: Decimal?
            if possession.purchaseCurrency == homeCurrency {
                converted = value
            } else {
                converted = cache.convert(amount: value, from: possession.purchaseCurrency, to: homeCurrency)
            }
            guard let value = converted else {
                missing.insert(possession.purchaseCurrency)
                continue
            }
            total += value
            sums[possession.category, default: 0] += value
        }
        let byCategory = sums
            .map { CategoryTotal(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
        return Bundle(
            totals: Totals(amount: total, missingCurrencies: missing.sorted()),
            byCategory: byCategory
        )
    }

    private static func categoryTotals(
        possessions: [Possession],
        homeCurrency: String,
        asOf: Date?,
        cache: FXService.RateCache
    ) -> [CategoryTotal] {
        var sums: [PossessionCategory: Decimal] = [:]
        for possession in possessions {
            guard let value = effectiveValue(for: possession, asOf: asOf) else { continue }
            let converted: Decimal?
            if possession.purchaseCurrency == homeCurrency {
                converted = value
            } else {
                converted = cache.convert(amount: value, from: possession.purchaseCurrency, to: homeCurrency)
            }
            guard let value = converted else { continue }
            sums[possession.category, default: 0] += value
        }
        return sums
            .map { CategoryTotal(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    private static func aggregate(
        possessions: [Possession],
        homeCurrency: String,
        asOf: Date?,
        cache: FXService.RateCache
    ) -> Totals {
        var total: Decimal = 0
        var missing: Set<String> = []
        for possession in possessions {
            guard let value = effectiveValue(for: possession, asOf: asOf) else { continue }
            if possession.purchaseCurrency == homeCurrency {
                total += value
            } else if let converted = cache.convert(
                amount: value,
                from: possession.purchaseCurrency,
                to: homeCurrency
            ) {
                total += converted
            } else {
                missing.insert(possession.purchaseCurrency)
            }
        }
        return Totals(amount: total, missingCurrencies: missing.sorted())
    }

    /// Returns the value an possession should contribute at a given cutoff.
    /// Current (asOf == nil): possession's `effectiveValue` unless sold.
    /// Historical (asOf != nil): purchase price for possessions purchased by the
    /// cutoff and not sold before or on it; `nil` otherwise.
    private static func effectiveValue(for possession: Possession, asOf: Date?) -> Decimal? {
        guard let asOf else { return possession.effectiveValue }
        guard possession.purchaseDate <= asOf else { return nil }
        if let saleDate = possession.saleDate, saleDate <= asOf { return nil }
        return possession.purchasePrice
    }
}

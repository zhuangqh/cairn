import Foundation
import SwiftData

// MARK: - Per-currency breakdown

extension NetWorthCalculator {
    /// Holdings of one currency, summed in their own currency and in the
    /// home currency. `convertedAmount` is `nil` when any contributing
    /// balance lacks an FX rate, so the currency is excluded from totals.
    public struct CurrencyTotal: Sendable, Equatable, Identifiable {
        public let currency: String
        public let nativeAmount: Decimal
        public let convertedAmount: Decimal?
        public var id: String { currency }
    }

    /// Per-currency breakdown of live holdings as of `periodMonth`, ordered
    /// like `sortedCurrencyTotals`.
    public static func totalsByCurrency(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        context: ModelContext
    ) -> [CurrencyTotal] {
        let index = SortedSnapshotIndex.load(in: context)
        let agg = aggregateFast(
            holdings: index.holdings,
            homeCurrency: homeCurrency,
            asOf: periodMonth,
            cache: FXService.RateCache.load(in: context),
            sortedSnapshots: index
        )
        return sortedCurrencyTotals(agg.byCurrency)
    }

    /// Per-currency breakdown of a captured portfolio snapshot, using the
    /// converted amounts frozen at capture time.
    public static func currencyTotals(in entries: [PortfolioSnapshot.Entry]) -> [CurrencyTotal] {
        var sums: [String: CurrencySum] = [:]
        for entry in entries {
            sums[entry.currency, default: CurrencySum()].add(native: entry.amount, converted: entry.convertedAmount)
        }
        return sortedCurrencyTotals(sums)
    }

    /// Running native + converted sum for one currency. A single missing
    /// conversion marks the whole currency as unconverted.
    @usableFromInline
    struct CurrencySum {
        var native: Decimal = 0
        var converted: Decimal? = 0

        mutating func add(native amount: Decimal, converted value: Decimal?) {
            native += amount
            if let value, let current = converted {
                converted = current + value
            } else {
                converted = nil
            }
        }
    }

    /// Drops zero balances, then orders non-negative converted totals
    /// largest first, negative totals after them, and currencies without
    /// an FX rate last (alphabetically).
    static func sortedCurrencyTotals(_ sums: [String: CurrencySum]) -> [CurrencyTotal] {
        let totals = sums
            .filter { $0.value.native != 0 }
            .map { CurrencyTotal(currency: $0.key, nativeAmount: $0.value.native, convertedAmount: $0.value.converted) }
        func rank(_ total: CurrencyTotal) -> Int {
            guard let value = total.convertedAmount else { return 2 }
            return value < 0 ? 1 : 0
        }
        return totals.sorted { lhs, rhs in
            let (lhsRank, rhsRank) = (rank(lhs), rank(rhs))
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if let lhsValue = lhs.convertedAmount, let rhsValue = rhs.convertedAmount, lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            return lhs.currency < rhs.currency
        }
    }
}

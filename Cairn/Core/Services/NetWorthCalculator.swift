import Foundation
import SwiftData

/// Computes aggregated asset values from the SwiftData store.
///
/// Each `Holding` is valued by its latest `Snapshot` at or before a given
/// `periodMonth`; amounts are converted to `homeCurrency` using cached
/// `FXRate` rows via `FXService.convert(...)`. Holdings whose currency
/// has no cached rate are reported separately as `missingCurrencies`.
@MainActor
public enum NetWorthCalculator {
    public struct Totals: Sendable, Equatable {
        public var amount: Decimal
        /// Currencies encountered that could not be converted to the home
        /// currency. The UI uses this to prompt for a rate refresh.
        public var missingCurrencies: [String]
    }

    public struct MemberTotal: Sendable, Equatable, Identifiable {
        public let memberId: UUID
        public let memberName: String
        public let amount: Decimal
        public var id: UUID { memberId }
    }

    /// Net worth across all holdings, valued at the latest snapshot on or
    /// before `periodMonth`.
    public static func total(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        context: ModelContext
    ) -> Totals {
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        return aggregate(
            holdings: holdings,
            homeCurrency: homeCurrency,
            asOf: periodMonth,
            context: context
        )
    }

    /// Per-member breakdown. Members with no holdings are omitted.
    public static func totalsByMember(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        context: ModelContext
    ) -> [MemberTotal] {
        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        return members.compactMap { member in
            let holdings = member.accounts?
                .flatMap { $0.holdings ?? [] } ?? []
            guard !holdings.isEmpty else { return nil }
            let totals = aggregate(
                holdings: holdings,
                homeCurrency: homeCurrency,
                asOf: periodMonth,
                context: context
            )
            return MemberTotal(
                memberId: member.id,
                memberName: member.name,
                amount: totals.amount
            )
        }
    }

    /// Monthly trend series. Each entry is `(periodMonth, totalInHomeCurrency)`.
    /// Returns the most recent `months` months up to and including the month
    /// containing `anchor`, sorted chronologically.
    public static func trend(
        homeCurrency: String,
        months: Int,
        anchor: Date = .now,
        context: ModelContext
    ) -> [(period: Date, amount: Decimal)] {
        guard months > 0 else { return [] }
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt

        let anchorMonth = Snapshot.normalize(anchor)
        let periods: [Date] = (0..<months).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: anchorMonth)
        }
        return periods.map { period in
            let totals = aggregate(
                holdings: holdings,
                homeCurrency: homeCurrency,
                asOf: period,
                context: context
            )
            return (period, totals.amount)
        }
    }

    // MARK: - Internals

    private static func aggregate(
        holdings: [Holding],
        homeCurrency: String,
        asOf periodMonth: Date,
        context: ModelContext
    ) -> Totals {
        let normalizedCutoff = Snapshot.normalize(periodMonth)
        var total: Decimal = 0
        var missing: Set<String> = []

        for holding in holdings where holding.isArchived == false {
            guard let amount = latestAmount(for: holding, asOf: normalizedCutoff) else { continue }
            if holding.currency == homeCurrency {
                total += amount
            } else if let converted = FXService.convert(
                amount: amount,
                from: holding.currency,
                to: homeCurrency,
                in: context
            ) {
                total += converted
            } else {
                missing.insert(holding.currency)
            }
        }

        return Totals(
            amount: total,
            missingCurrencies: missing.sorted()
        )
    }

    private static func latestAmount(for holding: Holding, asOf cutoff: Date) -> Decimal? {
        let snapshots = (holding.snapshots ?? [])
            .filter { $0.periodMonth <= cutoff }
            .sorted { $0.periodMonth > $1.periodMonth }
        return snapshots.first?.amount
    }
}

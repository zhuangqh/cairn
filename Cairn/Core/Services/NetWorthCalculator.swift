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

    public struct KindTotal: Sendable, Equatable, Identifiable {
        public let kind: AccountKind
        public let amount: Decimal
        public var id: AccountKind { kind }
    }

    public struct Activity: Sendable, Identifiable {
        public let id: UUID
        public let recordedAt: Date
        public let periodMonth: Date
        public let memberName: String
        public let accountName: String
        public let holdingLabel: String?
        public let currency: String
        public let amount: Decimal
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

    /// Net-worth totals broken down by account kind (cash/stock/realEstate/device),
    /// valued at the latest snapshot on or before `periodMonth`. Only kinds with
    /// non-zero totals are returned, sorted by amount descending.
    public static func totalsByKind(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        context: ModelContext
    ) -> [KindTotal] {
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        let normalizedCutoff = cutoffEndOfMonth(for: periodMonth)
        var sums: [AccountKind: Decimal] = [:]

        for holding in holdings where holding.isArchived == false {
            guard let account = holding.account, account.isArchived == false else { continue }
            guard let amount = latestAmount(for: holding, asOf: normalizedCutoff) else { continue }
            let converted: Decimal?
            if holding.currency == homeCurrency {
                converted = amount
            } else {
                converted = FXService.convert(
                    amount: amount,
                    from: holding.currency,
                    to: homeCurrency,
                    in: context
                )
            }
            guard let value = converted else { continue }
            sums[account.kind, default: 0] += value
        }

        return sums
            .filter { $0.value != 0 }
            .map { KindTotal(kind: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// Percentage change between `asOf` month total and the preceding month total.
    /// Returns `nil` when the previous month has zero net worth (no baseline).
    public static func monthOverMonthDelta(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        context: ModelContext
    ) -> Double? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let thisMonth = Snapshot.normalize(periodMonth)
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) else { return nil }

        let current = total(homeCurrency: homeCurrency, asOf: thisMonth, context: context).amount
        let previous = total(homeCurrency: homeCurrency, asOf: lastMonth, context: context).amount
        guard previous != 0 else { return nil }
        let change = (current - previous) / previous
        return NSDecimalNumber(decimal: change).doubleValue
    }

    /// The most recently recorded snapshots across the whole store. Each entry
    /// carries resolved member / account / holding context for display.
    public static func recentActivities(
        limit: Int = 10,
        context: ModelContext
    ) -> [Activity] {
        var descriptor = FetchDescriptor<Snapshot>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { snapshot in
            let holding = snapshot.holding
            let account = holding?.account
            let member = account?.member
            return Activity(
                id: snapshot.id,
                recordedAt: snapshot.recordedAt,
                periodMonth: snapshot.periodMonth,
                memberName: member?.name ?? "",
                accountName: account?.name ?? "",
                holdingLabel: holding?.label,
                currency: holding?.currency ?? "",
                amount: snapshot.amount
            )
        }
    }

    // MARK: - Internals

    private static func aggregate(
        holdings: [Holding],
        homeCurrency: String,
        asOf periodMonth: Date,
        context: ModelContext
    ) -> Totals {
        let normalizedCutoff = cutoffEndOfMonth(for: periodMonth)
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

    /// Returns the last instant of the month that contains `periodMonth`, so
    /// day-granular snapshots recorded anywhere within the cutoff's month
    /// are included in "as of" queries. Expressed as `startOfNextMonth - 1s`
    /// so the `<=` filter remains inclusive of the final day.
    private static func cutoffEndOfMonth(for periodMonth: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let monthStart = Snapshot.normalize(periodMonth)
        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return monthStart
        }
        return nextMonthStart.addingTimeInterval(-1)
    }
}

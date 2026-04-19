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

    /// One-shot bundle of every aggregate the UI typically asks for in the
    /// same render pass — total, per-member, per-kind, missing currencies,
    /// and the month-over-month delta — computed from a single holdings
    /// fetch + a single FX-rate cache. Designed to be the only entry point
    /// the dashboards / overview screens need.
    public struct Bundle: Sendable, Equatable {
        public var totals: Totals
        public var byKind: [KindTotal]
        public var byMember: [MemberTotal]
        /// Percentage change vs the previous month, or `nil` when the
        /// previous month was zero.
        public var monthOverMonthDelta: Double?
    }

    /// Computes `Bundle` for a single `asOf` month. Optionally accepts a
    /// pre-loaded rate cache so multiple bundles (e.g. across a trend
    /// window) can share one cache.
    public static func bundle(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        includeMemberBreakdown: Bool = true,
        rateCache: FXService.RateCache? = nil,
        sortedSnapshots: SortedSnapshotIndex? = nil,
        context: ModelContext
    ) -> Bundle {
        let cache = rateCache ?? FXService.RateCache.load(in: context)
        let index = sortedSnapshots ?? SortedSnapshotIndex.load(in: context)
        let holdings = index.holdings

        let current = aggregateFast(
            holdings: holdings,
            homeCurrency: homeCurrency,
            asOf: periodMonth,
            cache: cache,
            sortedSnapshots: index
        )

        let kindMap = current.byKind
        let kindTotals = kindMap
            .filter { $0.value != 0 }
            .map { KindTotal(kind: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        let memberTotals: [MemberTotal] = includeMemberBreakdown
            ? buildMemberTotals(byMember: current.byMember, in: context)
            : []

        let delta = priorMonthDelta(
            currentTotal: current.total,
            asOf: periodMonth,
            inputs: AggregationInputs(
                holdings: holdings,
                homeCurrency: homeCurrency,
                cache: cache,
                index: index
            )
        )

        return Bundle(
            totals: Totals(amount: current.total, missingCurrencies: current.missing.sorted()),
            byKind: kindTotals,
            byMember: memberTotals,
            monthOverMonthDelta: delta
        )
    }

    private static func buildMemberTotals(
        byMember: [UUID: (name: String, amount: Decimal)],
        in context: ModelContext
    ) -> [MemberTotal] {
        // Iterate `Member` rows in their natural fetch order so the
        // resulting list matches what `totalsByMember` returns and what
        // existing UI ordering expects.
        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        return members.compactMap { member in
            guard let entry = byMember[member.id] else { return nil }
            return MemberTotal(memberId: member.id, memberName: member.name, amount: entry.amount)
        }
    }

    /// Bag of inputs shared by every aggregation pass in a single bundle
    /// computation. Lets `priorMonthDelta` keep its parameter list short.
    private struct AggregationInputs {
        let holdings: [Holding]
        let homeCurrency: String
        let cache: FXService.RateCache
        let index: SortedSnapshotIndex
    }

    private static func priorMonthDelta(
        currentTotal: Decimal,
        asOf periodMonth: Date,
        inputs: AggregationInputs
    ) -> Double? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let thisMonth = Snapshot.normalize(periodMonth)
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) else { return nil }
        let prev = aggregateFast(
            holdings: inputs.holdings,
            homeCurrency: inputs.homeCurrency,
            asOf: lastMonth,
            cache: inputs.cache,
            sortedSnapshots: inputs.index
        )
        guard prev.total != 0 else { return nil }
        let change = (currentTotal - prev.total) / prev.total
        return NSDecimalNumber(decimal: change).doubleValue
    }

    /// Net worth across all holdings, valued at the latest snapshot on or
    /// before `periodMonth`.
    public static func total(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        context: ModelContext
    ) -> Totals {
        let cache = FXService.RateCache.load(in: context)
        let index = SortedSnapshotIndex.load(in: context)
        let agg = aggregateFast(
            holdings: index.holdings,
            homeCurrency: homeCurrency,
            asOf: periodMonth,
            cache: cache,
            sortedSnapshots: index
        )
        return Totals(amount: agg.total, missingCurrencies: agg.missing.sorted())
    }

    /// Per-member breakdown. Members with no holdings are omitted.
    public static func totalsByMember(
        homeCurrency: String,
        asOf periodMonth: Date = .now,
        context: ModelContext
    ) -> [MemberTotal] {
        // Preserve existing semantics: iterate `Member`s in their fetch order
        // (matches previous behaviour & test expectations).
        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        let cache = FXService.RateCache.load(in: context)
        let index = SortedSnapshotIndex.load(in: context)
        return members.compactMap { member in
            let holdings = member.accounts?
                .flatMap { $0.holdings ?? [] } ?? []
            guard !holdings.isEmpty else { return nil }
            let agg = aggregateFast(
                holdings: holdings,
                homeCurrency: homeCurrency,
                asOf: periodMonth,
                cache: cache,
                sortedSnapshots: index
            )
            return MemberTotal(
                memberId: member.id,
                memberName: member.name,
                amount: agg.total
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
        let cache = FXService.RateCache.load(in: context)
        let index = SortedSnapshotIndex.load(in: context)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt

        let anchorMonth = Snapshot.normalize(anchor)
        let periods: [Date] = (0..<months).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: anchorMonth)
        }
        return periods.map { period in
            let agg = aggregateFast(
                holdings: index.holdings,
                homeCurrency: homeCurrency,
                asOf: period,
                cache: cache,
                sortedSnapshots: index
            )
            return (period, agg.total)
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
        let cache = FXService.RateCache.load(in: context)
        let index = SortedSnapshotIndex.load(in: context)
        let agg = aggregateFast(
            holdings: index.holdings,
            homeCurrency: homeCurrency,
            asOf: periodMonth,
            cache: cache,
            sortedSnapshots: index
        )
        return agg.byKind
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

        let cache = FXService.RateCache.load(in: context)
        let index = SortedSnapshotIndex.load(in: context)
        let current = aggregateFast(
            holdings: index.holdings,
            homeCurrency: homeCurrency,
            asOf: thisMonth,
            cache: cache,
            sortedSnapshots: index
        ).total
        let previous = aggregateFast(
            holdings: index.holdings,
            homeCurrency: homeCurrency,
            asOf: lastMonth,
            cache: cache,
            sortedSnapshots: index
        ).total
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

    /// Per-holding snapshot index, ordered ascending by `periodMonth`.
    /// Built once from a single SwiftData fetch so that repeated "latest
    /// snapshot at or before X" lookups across many `asOf` cutoffs share
    /// the same sorted arrays.
    public struct SortedSnapshotIndex: Sendable {
        /// All holdings present in the store. Includes archived rows so
        /// callers can apply their own filters; aggregation skips archived
        /// holdings / accounts.
        public let holdings: [Holding]
        /// Snapshots per holding `id`, sorted ascending by `periodMonth`.
        @usableFromInline let byHoldingId: [UUID: [Snapshot]]

        @usableFromInline
        init(holdings: [Holding], byHoldingId: [UUID: [Snapshot]]) {
            self.holdings = holdings
            self.byHoldingId = byHoldingId
        }

        public static func load(in context: ModelContext) -> SortedSnapshotIndex {
            let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
            // Fetch all snapshots in one query and bucket by holding id;
            // avoids N relationship round-trips through `holding.snapshots`
            // when we have many holdings.
            let snapshots = (try? context.fetch(
                FetchDescriptor<Snapshot>(sortBy: [SortDescriptor(\.periodMonth, order: .forward)])
            )) ?? []
            var byHolding: [UUID: [Snapshot]] = [:]
            byHolding.reserveCapacity(holdings.count)
            for snap in snapshots {
                guard let hid = snap.holding?.id else { continue }
                byHolding[hid, default: []].append(snap)
            }
            return SortedSnapshotIndex(holdings: holdings, byHoldingId: byHolding)
        }

        /// Latest snapshot amount at or before `cutoff` for `holding`.
        /// Linear scan from the tail of the ascending array — typically a
        /// few comparisons because the cutoff is usually near "now".
        @inlinable
        public func latestAmount(for holding: Holding, asOf cutoff: Date) -> Decimal? {
            guard let arr = byHoldingId[holding.id] else { return nil }
            // Walk from newest backwards; bail at first <= cutoff.
            var index = arr.count - 1
            while index >= 0 {
                let snap = arr[index]
                if snap.periodMonth <= cutoff { return snap.amount }
                index -= 1
            }
            return nil
        }
    }

    @usableFromInline
    struct AggregateResult {
        var total: Decimal
        var missing: Set<String>
        var byKind: [AccountKind: Decimal]
        var byMember: [UUID: (name: String, amount: Decimal)]
    }

    /// Single-pass aggregator. Walks every active holding once, valuing it
    /// from the pre-sorted snapshot index and converting via the in-memory
    /// FX cache. Produces total, per-kind, per-member, and missing
    /// currencies in one go — callers pick what they need.
    @usableFromInline
    static func aggregateFast(
        holdings: [Holding],
        homeCurrency: String,
        asOf periodMonth: Date,
        cache: FXService.RateCache,
        sortedSnapshots: SortedSnapshotIndex
    ) -> AggregateResult {
        let cutoff = cutoffEndOfMonth(for: periodMonth)
        var total: Decimal = 0
        var missing: Set<String> = []
        var byKind: [AccountKind: Decimal] = [:]
        var byMember: [UUID: (name: String, amount: Decimal)] = [:]

        for holding in holdings where holding.isArchived == false {
            guard let account = holding.account, account.isArchived == false else { continue }
            guard let amount = sortedSnapshots.latestAmount(for: holding, asOf: cutoff) else { continue }
            let converted: Decimal?
            if holding.currency == homeCurrency {
                converted = amount
            } else {
                converted = cache.convert(amount: amount, from: holding.currency, to: homeCurrency)
            }
            guard let value = converted else {
                missing.insert(holding.currency)
                continue
            }
            total += value
            byKind[account.kind, default: 0] += value
            if let member = account.member {
                let prev = byMember[member.id]?.amount ?? 0
                byMember[member.id] = (member.name, prev + value)
            }
        }

        return AggregateResult(total: total, missing: missing, byKind: byKind, byMember: byMember)
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

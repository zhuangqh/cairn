import Foundation
import SwiftData

/// Derives the Assets financial summary — headline total, per-member and
/// per-currency breakdowns, and their deltas — in one pass.
///
/// Once a portfolio snapshot exists in the home currency, the summary is a
/// view of the latest one so every figure shares its frozen balances and
/// FX rates. Before that, it falls back to the live holdings calculation.
@MainActor
enum AssetsSummaryService {
    struct Summary {
        var totals: NetWorthCalculator.Totals
        var memberTotals: [NetWorthCalculator.MemberTotal]
        /// Month-over-month percentage delta for the household total.
        var monthDeltaPercent: Double?
        /// Month-over-month absolute delta in `homeCurrency`.
        var monthDeltaAmount: Decimal?
        /// Per-member month-over-month percentage deltas, keyed by id.
        var memberDeltaPercent: [UUID: Double]
        var currencyTotals: [NetWorthCalculator.CurrencyTotal]
        /// Per-currency month-over-month percentage deltas, keyed by code.
        var currencyDeltaPercent: [String: Double]
        /// The source snapshot when the displayed values are captured history.
        var sourceSnapshot: PortfolioSnapshot?
    }

    /// Before the first portfolio snapshot exists, retain the live
    /// calculation so the empty state still gives the user a useful total.
    static func liveSummary(homeCurrency: String, context: ModelContext) -> Summary {
        // One rate cache + snapshot index serves every aggregate below.
        let rateCache = FXService.RateCache.load(in: context)
        let snapshotIndex = NetWorthCalculator.SortedSnapshotIndex.load(in: context)
        let bundle = NetWorthCalculator.bundle(
            homeCurrency: homeCurrency,
            includeMemberBreakdown: true,
            rateCache: rateCache, sortedSnapshots: snapshotIndex,
            context: context
        )

        // Prior month — computed once, reused for absolute delta + per-member.
        let thisMonth = Snapshot.normalize(.now)
        let lastMonth = Snapshot.adding(months: -1, to: thisMonth)

        var deltaAmount: Decimal?
        var memberDeltas: [UUID: Double] = [:]
        var currencyDeltas: [String: Double] = [:]

        if let lastMonth {
            let prevTotal = NetWorthCalculator.total(
                homeCurrency: homeCurrency,
                asOf: lastMonth,
                rateCache: rateCache, sortedSnapshots: snapshotIndex,
                context: context
            )
            deltaAmount = bundle.totals.amount - prevTotal.amount

            let prevMembers = NetWorthCalculator.totalsByMember(
                homeCurrency: homeCurrency,
                asOf: lastMonth,
                rateCache: rateCache, sortedSnapshots: snapshotIndex,
                context: context
            )
            let prevById = Dictionary(uniqueKeysWithValues: prevMembers.map { ($0.memberId, $0.amount) })
            for entry in bundle.byMember {
                guard let prior = prevById[entry.memberId],
                      let change = NetWorthCalculator.percentChange(current: entry.amount, previous: prior) else { continue }
                memberDeltas[entry.memberId] = change
            }

            currencyDeltas = currencyDeltaPercents(
                current: bundle.byCurrency,
                previous: NetWorthCalculator.totalsByCurrency(
                    homeCurrency: homeCurrency,
                    asOf: lastMonth,
                    rateCache: rateCache, sortedSnapshots: snapshotIndex,
                    context: context
                )
            )
        }

        return Summary(
            totals: bundle.totals,
            memberTotals: bundle.byMember,
            monthDeltaPercent: bundle.monthOverMonthDelta,
            monthDeltaAmount: deltaAmount,
            memberDeltaPercent: memberDeltas,
            currencyTotals: bundle.byCurrency,
            currencyDeltaPercent: currencyDeltas,
            sourceSnapshot: nil
        )
    }

    /// Once history exists, the Assets summary is a view of the latest
    /// captured portfolio snapshot. This keeps the headline, member totals,
    /// and deltas on the same frozen balances and FX rates.
    ///
    /// `members` resolve entries to member totals, and their order is the
    /// member row order; `holdings` map entries to members via live accounts.
    static func summary(
        from latest: PortfolioSnapshot,
        previous: PortfolioSnapshot?,
        members: [Member],
        holdings: [Holding]
    ) -> Summary {
        let holdingsById = Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0) })
        let latestMembers = memberTotals(in: latest, members: members, holdingsById: holdingsById)
        let previousById = Dictionary(
            uniqueKeysWithValues: previous
                .map { memberTotals(in: $0, members: members, holdingsById: holdingsById) }?
                .map { ($0.memberId, $0.amount) } ?? []
        )

        let deltaAmount = previous.map { latest.totalAmount - $0.totalAmount }
        let deltaPercent: Double? = previous.flatMap { prior in
            NetWorthCalculator.percentChange(current: latest.totalAmount, previous: prior.totalAmount)
        }

        var memberDeltas: [UUID: Double] = [:]
        for entry in latestMembers {
            guard let prior = previousById[entry.memberId],
                  let change = NetWorthCalculator.percentChange(current: entry.amount, previous: prior) else { continue }
            memberDeltas[entry.memberId] = change
        }

        let latestCurrencies = NetWorthCalculator.currencyTotals(in: latest.entries)
        return Summary(
            totals: .init(amount: latest.totalAmount, missingCurrencies: []),
            memberTotals: latestMembers,
            monthDeltaPercent: deltaPercent,
            monthDeltaAmount: deltaAmount,
            memberDeltaPercent: memberDeltas,
            currencyTotals: latestCurrencies,
            currencyDeltaPercent: currencyDeltaPercents(
                current: latestCurrencies,
                previous: previous.map { NetWorthCalculator.currencyTotals(in: $0.entries) } ?? []
            ),
            sourceSnapshot: latest
        )
    }

    /// Converted-amount change per currency; skipped when either side lacks
    /// a rate or the prior balance is zero.
    private static func currencyDeltaPercents(
        current: [NetWorthCalculator.CurrencyTotal],
        previous: [NetWorthCalculator.CurrencyTotal]
    ) -> [String: Double] {
        let priorByCode = Dictionary(uniqueKeysWithValues: previous.map { ($0.currency, $0.convertedAmount) })
        var deltas: [String: Double] = [:]
        for entry in current {
            guard let value = entry.convertedAmount,
                  let prior = priorByCode[entry.currency] ?? nil,
                  let change = NetWorthCalculator.percentChange(current: value, previous: prior) else { continue }
            deltas[entry.currency] = change
        }
        return deltas
    }

    /// Sums each snapshot entry's converted amount onto its member, resolved
    /// through the live holding first and the captured member name second.
    private static func memberTotals(
        in snapshot: PortfolioSnapshot,
        members: [Member],
        holdingsById: [UUID: Holding]
    ) -> [NetWorthCalculator.MemberTotal] {
        var amountsByMemberId: [UUID: Decimal] = [:]

        for entry in snapshot.entries {
            guard let amount = entry.convertedAmount else { continue }
            let resolvedMember = entry.holdingId
                .flatMap { holdingsById[$0]?.account?.member }
                ?? members.first(where: { $0.name == entry.memberName })
            guard let resolvedMember else { continue }
            amountsByMemberId[resolvedMember.id, default: 0] += amount
        }

        return members.compactMap { member in
            guard let amount = amountsByMemberId[member.id] else { return nil }
            return NetWorthCalculator.MemberTotal(
                memberId: member.id,
                memberName: member.name,
                amount: amount
            )
        }
    }
}

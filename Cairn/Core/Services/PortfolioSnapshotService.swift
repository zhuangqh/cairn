import Foundation
import SwiftData

/// Business rules for `PortfolioSnapshot`.
///
/// A portfolio snapshot is the aggregate form of a month's batch entry:
/// one record per `(periodMonth, homeCurrency)` that captures the user's
/// per-holding values (already saved as `Snapshot` rows by the batch
/// upsert) together with the FX rates in effect at the time of save.
/// The total is precomputed so historical trend points stay stable even
/// if individual rates or values are edited later.
@MainActor
public enum PortfolioSnapshotService {

    /// Creates or updates the `PortfolioSnapshot` for the given month
    /// using whatever `Snapshot` rows are currently saved.
    ///
    /// FX rates are sourced from `fetcher` at the *target month's
    /// reference date* (end of month, or today if the month is current /
    /// future) so historical snapshots reflect the rate that was in
    /// effect at the time of the month, not today's rate. On network
    /// failure we fall back to the local FX cache so the snapshot is
    /// still saved.
    ///
    /// Intended to be called right after `BatchUpsertService.apply(...)`.
    @discardableResult
    public static func captureForMonth(
        _ periodMonth: Date,
        homeCurrency: String,
        note: String? = nil,
        fetcher: any FXRateFetching = FrankfurterFetcher(),
        context: ModelContext,
        now: Date = .now
    ) async throws -> PortfolioSnapshot {
        let normalized = Snapshot.normalize(periodMonth)
        let referenceDate = referenceDate(for: normalized, now: now)
        let data = try await buildSnapshotData(
            periodMonth: normalized,
            referenceDate: referenceDate,
            homeCurrency: homeCurrency,
            fetcher: fetcher,
            context: context
        )

        if let existing = find(periodMonth: normalized, homeCurrency: homeCurrency, context: context) {
            existing.totalAmount = data.total
            existing.entries = data.entries
            existing.rates = data.rates
            existing.recordedAt = now
            if let note { existing.note = note }
            try context.save()
            return existing
        }

        let snapshot = PortfolioSnapshot(
            periodMonth: normalized,
            homeCurrency: homeCurrency,
            totalAmount: data.total,
            entries: data.entries,
            rates: data.rates,
            note: note,
            recordedAt: now
        )
        context.insert(snapshot)
        try context.save()
        return snapshot
    }

    /// Deletes a captured portfolio snapshot together with the underlying
    /// per-holding `Snapshot` rows that fed into it. Per-holding snapshots
    /// are day-granular, so we clear every `Snapshot` that falls inside
    /// the portfolio snapshot's month for any of the captured holdings.
    public static func delete(_ snapshot: PortfolioSnapshot, context: ModelContext) throws {
        let monthStart = snapshot.periodMonth
        let monthEnd = Self.nextMonthStart(after: monthStart)
        let holdingIds = Set(snapshot.entries.compactMap(\.holdingId))
        if !holdingIds.isEmpty {
            let descriptor = FetchDescriptor<Snapshot>(
                predicate: #Predicate { $0.periodMonth >= monthStart && $0.periodMonth < monthEnd }
            )
            let monthlySnapshots = (try? context.fetch(descriptor)) ?? []
            for row in monthlySnapshots {
                guard let holdingId = row.holding?.id, holdingIds.contains(holdingId) else { continue }
                context.delete(row)
            }
        }
        context.delete(snapshot)
        try context.save()
    }

    /// First instant of the month following `monthStart` in UTC.
    private static func nextMonthStart(after monthStart: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }

    /// All portfolio snapshots, ordered by `periodMonth` descending.
    public static func all(context: ModelContext) -> [PortfolioSnapshot] {
        let descriptor = FetchDescriptor<PortfolioSnapshot>(
            sortBy: [SortDescriptor(\.periodMonth, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Internals

    /// The date we ask the FX provider about for a given month. We use
    /// the last day of the month so that the snapshot reflects the
    /// period's closing rate. For the current / future month we fall
    /// back to `now` because the closing rate isn't known yet.
    private static func referenceDate(for normalizedMonth: Date, now: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let currentMonth = Snapshot.normalize(now)
        if normalizedMonth >= currentMonth { return now }
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: normalizedMonth),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) else {
            return normalizedMonth
        }
        return lastDay
    }

    private static func find(
        periodMonth: Date,
        homeCurrency: String,
        context: ModelContext
    ) -> PortfolioSnapshot? {
        let month = periodMonth
        let currency = homeCurrency
        var descriptor = FetchDescriptor<PortfolioSnapshot>(
            predicate: #Predicate { $0.periodMonth == month && $0.homeCurrency == currency }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private struct SnapshotData {
        var entries: [PortfolioSnapshot.Entry]
        var rates: [PortfolioSnapshot.Rate]
        var total: Decimal
    }

    private static func buildSnapshotData(
        periodMonth: Date,
        referenceDate: Date,
        homeCurrency: String,
        fetcher: any FXRateFetching,
        context: ModelContext
    ) async throws -> SnapshotData {
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        let activeHoldings = holdings.filter { $0.isArchived == false && $0.account?.isArchived == false }
        let quotes = activeHoldings
            .map(\.currency)
            .reduce(into: Set<String>()) { $0.insert($1) }
            .filter { $0 != homeCurrency }
            .sorted()

        let historicalRates = await fetchHistoricalRates(
            base: homeCurrency,
            quotes: quotes,
            on: referenceDate,
            fetcher: fetcher,
            context: context
        )

        let (entries, total) = makeEntries(
            holdings: activeHoldings,
            periodMonth: periodMonth,
            homeCurrency: homeCurrency,
            historicalRates: historicalRates,
            context: context
        )

        let rates = historicalRates
            .filter { $0.key != homeCurrency }
            .map { PortfolioSnapshot.Rate(base: homeCurrency, quote: $0.key, rate: $0.value) }
            .sorted { $0.quote < $1.quote }

        return SnapshotData(entries: entries, rates: rates, total: total)
    }

    private static func makeEntries(
        holdings: [Holding],
        periodMonth: Date,
        homeCurrency: String,
        historicalRates: [String: Decimal],
        context: ModelContext
    ) -> (entries: [PortfolioSnapshot.Entry], total: Decimal) {
        var entries: [PortfolioSnapshot.Entry] = []
        var total: Decimal = 0

        for holding in holdings {
            guard let account = holding.account else { continue }
            guard let amount = latestAmount(for: holding, asOf: periodMonth) else { continue }

            let converted = convert(
                amount: amount,
                from: holding.currency,
                to: homeCurrency,
                using: historicalRates,
                fallbackContext: context
            )
            if let value = converted { total += value }

            entries.append(
                PortfolioSnapshot.Entry(
                    holdingId: holding.id,
                    memberName: account.member?.name ?? "",
                    accountName: account.name,
                    accountKindRawValue: account.kindRawValue,
                    holdingLabel: holding.label,
                    currency: holding.currency,
                    amount: amount,
                    convertedAmount: converted
                )
            )
        }

        entries.sort { lhs, rhs in
            if lhs.memberName == rhs.memberName {
                if lhs.accountName == rhs.accountName {
                    return lhs.currency < rhs.currency
                }
                return lhs.accountName < rhs.accountName
            }
            return lhs.memberName < rhs.memberName
        }

        return (entries, total)
    }

    /// Asks `fetcher` for historical rates on `date`. Falls back to the
    /// local FX cache when the network is unavailable so capture still
    /// succeeds (just with today's rates instead of the target date's).
    private static func fetchHistoricalRates(
        base: String,
        quotes: [String],
        on date: Date,
        fetcher: any FXRateFetching,
        context: ModelContext
    ) async -> [String: Decimal] {
        guard !quotes.isEmpty else { return [:] }
        do {
            let response = try await fetcher.fetch(base: base, quotes: quotes, on: date)
            if !response.rates.isEmpty { return response.rates }
        } catch {
            #if DEBUG
            print("[PortfolioSnapshot] historical FX fetch failed: \(error)")
            #endif
        }
        // Fallback: whatever the local cache has (may be today's rate).
        var fallback: [String: Decimal] = [:]
        for quote in quotes {
            if let direct = FXService.latestRate(base: base, quote: quote, in: context) {
                fallback[quote] = direct.rate
            } else if let inverse = FXService.latestRate(base: quote, quote: base, in: context),
                      inverse.rate != 0 {
                fallback[quote] = 1 / inverse.rate
            }
        }
        return fallback
    }

    /// Converts `amount` (denominated in `from`) to `home`.
    ///
    /// `rates` is the dictionary returned by `fetchHistoricalRates`, keyed by
    /// the *foreign* (quote) currency. Per `FXRateFetching`'s contract —
    /// `1 base == rate × quote` — and because we fetched with `base = home`,
    /// the stored rate means `1 home = rate × foreign`, i.e. `rate` has units
    /// `foreign / home`. To land the result in `home` units we therefore
    /// divide by the rate (equivalently, multiply by `home / foreign`).
    private static func convert(
        amount: Decimal,
        from: String,
        to home: String,
        using rates: [String: Decimal],
        fallbackContext: ModelContext
    ) -> Decimal? {
        if from == home { return amount }
        if let rate = rates[from], rate != 0 { return amount / rate }
        return FXService.convert(amount: amount, from: from, to: home, in: fallbackContext)
    }

    private static func latestAmount(for holding: Holding, asOf cutoff: Date) -> Decimal? {
        // Expand the cutoff to the last instant of its containing month so
        // day-granular snapshots recorded within that month are included.
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let monthStart = Snapshot.normalize(cutoff)
        let effective: Date
        if let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) {
            effective = nextMonthStart.addingTimeInterval(-1)
        } else {
            effective = cutoff
        }
        let snapshots = (holding.snapshots ?? [])
            .filter { $0.periodMonth <= effective }
            .sorted { $0.periodMonth > $1.periodMonth }
        return snapshots.first?.amount
    }
}

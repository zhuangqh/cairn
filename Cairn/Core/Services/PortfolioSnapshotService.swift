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
enum PortfolioSnapshotService {

    /// Creates or updates the `PortfolioSnapshot` for the given snapshot date
    /// using whatever `Snapshot` rows are currently saved.
    ///
    /// FX rates are sourced from `fetcher` at the exact picked day (capped at
    /// today for future dates) so captured batches reflect the rate date the
    /// user saw in the batch entry sheet. On network
    /// failure we fall back to the local FX cache so the snapshot is
    /// still saved.
    ///
    /// Batch entry uses `BatchUpsertService.saveBatch(...)` instead, which
    /// saves the per-holding rows and this capture together.
    @discardableResult
    static func captureForMonth(
        _ periodMonth: Date,
        homeCurrency: String,
        note: String? = nil,
        fetcher: any FXRateFetching = FrankfurterFetcher(),
        context: ModelContext,
        now: Date = .now
    ) async throws -> PortfolioSnapshot {
        let rates = try await captureRates(
            for: periodMonth,
            homeCurrency: homeCurrency,
            fetcher: fetcher,
            context: context,
            now: now
        )
        let snapshot = try stageCapture(
            periodMonth,
            homeCurrency: homeCurrency,
            note: note,
            historicalRates: rates,
            context: context,
            now: now
        )
        try context.save()
        return snapshot
    }

    /// Rates for capturing `periodMonth`, keyed by foreign currency with
    /// `base = homeCurrency`: the provider's rates for the picked day
    /// (capped at `now`), else the local FX cache.
    static func captureRates(
        for periodMonth: Date,
        homeCurrency: String,
        fetcher: any FXRateFetching,
        context: ModelContext,
        fetching store: (any ModelFetching)? = nil,
        now: Date = .now
    ) async throws -> [String: Decimal] {
        let day = Snapshot.normalizeDay(periodMonth)
        let quotes = try activeHoldings(in: store ?? context)
            .map(\.currency)
            .reduce(into: Set<String>()) { $0.insert($1) }
            .filter { $0 != homeCurrency }
            .sorted()
        return await fetchHistoricalRates(
            base: homeCurrency,
            quotes: quotes,
            on: referenceDate(for: day, now: now),
            fetcher: fetcher,
            context: context
        )
    }

    /// Inserts or updates the `PortfolioSnapshot` for `periodMonth` from the
    /// holding amounts currently in `context`, including unsaved ones,
    /// without saving. Synchronous so callers can stage it together with
    /// the per-holding rows and commit both in one save.
    @discardableResult
    static func stageCapture(
        _ periodMonth: Date,
        homeCurrency: String,
        note: String?,
        historicalRates: [String: Decimal],
        context: ModelContext,
        fetching: (any ModelFetching)? = nil,
        now: Date = .now
    ) throws -> PortfolioSnapshot {
        let store = fetching ?? context
        let day = Snapshot.normalizeDay(periodMonth)
        let normalized = Snapshot.normalize(day)
        let (entries, total) = makeEntries(
            holdings: try activeHoldings(in: store),
            periodMonth: day,
            homeCurrency: homeCurrency,
            historicalRates: historicalRates,
            context: context
        )
        let rates = historicalRates
            .filter { $0.key != homeCurrency }
            .map { PortfolioSnapshot.Rate(base: homeCurrency, quote: $0.key, rate: $0.value) }
            .sorted { $0.quote < $1.quote }

        if let existing = try find(periodMonth: normalized, homeCurrency: homeCurrency, in: store) {
            existing.totalAmount = total
            existing.entries = entries
            existing.rates = rates
            existing.recordedAt = now
            existing.note = note
            return existing
        }

        let snapshot = PortfolioSnapshot(
            periodMonth: normalized,
            homeCurrency: homeCurrency,
            totalAmount: total,
            entries: entries,
            rates: rates,
            note: note,
            recordedAt: now
        )
        context.insert(snapshot)
        return snapshot
    }

    /// Deletes a captured portfolio snapshot together with the underlying
    /// per-holding `Snapshot` rows that fed into it. Per-holding snapshots
    /// are day-granular, so we clear every `Snapshot` that falls inside
    /// the portfolio snapshot's month for any of the captured holdings.
    static func delete(_ snapshot: PortfolioSnapshot, context: ModelContext) throws {
        let monthStart = snapshot.periodMonth
        let monthEnd = Snapshot.nextMonthStart(after: monthStart)
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
        try AchievementService.recompute(in: context)
    }

    /// Best-effort reconstruction of the concrete day the user picked when
    /// saving a monthly portfolio snapshot. The portfolio row itself is keyed
    /// by month, while the underlying per-holding `Snapshot` rows are
    /// day-granular, so we choose the day in that month with the most matching
    /// captured holding amounts.
    static func capturedDate(for snapshot: PortfolioSnapshot, context: ModelContext) -> Date {
        let holdingSnapshots = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []
        return capturedDate(for: snapshot, holdingSnapshots: holdingSnapshots)
    }

    // MARK: - Internals

    static func capturedDate(for snapshot: PortfolioSnapshot, holdingSnapshots: [Snapshot]) -> Date {
        let holdingIds = Set(snapshot.entries.compactMap(\.holdingId))
        guard !holdingIds.isEmpty else { return snapshot.periodMonth }

        let monthStart = snapshot.periodMonth
        let monthEnd = Snapshot.nextMonthStart(after: monthStart)
        let expectedAmountByHoldingId = Dictionary(
            snapshot.entries.compactMap { entry -> (UUID, Decimal)? in
                guard let holdingId = entry.holdingId else { return nil }
                return (holdingId, entry.amount)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var matchesByDate: [Date: Int] = [:]
        for row in holdingSnapshots {
            guard let holdingId = row.holding?.id, holdingIds.contains(holdingId) else { continue }
            guard row.periodMonth >= monthStart && row.periodMonth < monthEnd else { continue }
            guard expectedAmountByHoldingId[holdingId] == row.amount else { continue }
            matchesByDate[row.periodMonth, default: 0] += 1
        }

        return matchesByDate
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .first?.key ?? snapshot.periodMonth
    }

    /// The date we ask the FX provider about: the exact picked day, capped at
    /// `now` because future rates are not available.
    private static func referenceDate(for periodDay: Date, now: Date) -> Date {
        min(Snapshot.normalizeDay(periodDay), now)
    }

    private static func find(
        periodMonth: Date,
        homeCurrency: String,
        in store: any ModelFetching
    ) throws -> PortfolioSnapshot? {
        let month = periodMonth
        let currency = homeCurrency
        var descriptor = FetchDescriptor<PortfolioSnapshot>(
            predicate: #Predicate { $0.periodMonth == month && $0.homeCurrency == currency }
        )
        descriptor.fetchLimit = 1
        return try store.fetch(descriptor).first
    }

    private static func activeHoldings(in store: any ModelFetching) throws -> [Holding] {
        try store.fetch(FetchDescriptor<Holding>())
            .filter { $0.isArchived == false && $0.account?.isArchived == false }
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

            let converted = FXService.convert(
                amount: amount,
                from: holding.currency,
                to: homeCurrency,
                historicalRates: historicalRates
            ) {
                FXService.convert(amount: amount, from: holding.currency, to: homeCurrency, in: context)
            }
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

    private static func latestAmount(for holding: Holding, asOf cutoff: Date) -> Decimal? {
        // Expand the cutoff to the last instant of its containing month so
        // day-granular snapshots recorded within that month are included.
        let effective = Snapshot.endOfMonth(containing: cutoff) ?? cutoff
        // Skip rows deleted but not yet saved: a staged month replacement
        // still lists them in the relationship until the save.
        let snapshots = (holding.snapshots ?? [])
            .filter { !$0.isDeleted && $0.periodMonth <= effective }
            .sorted { $0.periodMonth > $1.periodMonth }
        return snapshots.first?.amount
    }
}

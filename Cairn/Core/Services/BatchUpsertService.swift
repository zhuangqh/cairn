import Foundation
import SwiftData

/// Atomic batch-upsert for the spreadsheet-style entry screen.
@MainActor
enum BatchUpsertService {
    /// A single pending edit from the grid.
    struct Row: Sendable {
        let holdingId: UUID
        let amount: Decimal?  // nil means "leave blank — no snapshot"

        init(holdingId: UUID, amount: Decimal?) {
            self.holdingId = holdingId
            self.amount = amount
        }
    }

    /// Saves a batch entry together with its `PortfolioSnapshot` in one
    /// save, so a failure leaves neither the per-holding rows nor the
    /// capture behind. FX rates are fetched before anything is staged:
    /// nothing awaits between staging and saving, so autosave cannot
    /// commit a partial batch while the network request is in flight.
    ///
    /// `replacingMonth` rewrites the month's rows for every holding in
    /// `rows` (editing a captured snapshot); otherwise non-nil rows are
    /// upserted on `periodMonth`'s day.
    @discardableResult
    static func saveBatch(
        _ rows: [Row],
        replacingMonth: Bool,
        periodMonth: Date,
        homeCurrency: String,
        note: String? = nil,
        fetcher: any FXRateFetching = FrankfurterFetcher(),
        context: ModelContext,
        fetching: (any ModelFetching)? = nil,
        now: Date = .now
    ) async throws -> PortfolioSnapshot {
        let store = fetching ?? context
        let rates = try await PortfolioSnapshotService.captureRates(
            for: periodMonth,
            homeCurrency: homeCurrency,
            fetcher: fetcher,
            context: context,
            fetching: store,
            now: now
        )
        return try saveOrRollback(context) {
            if replacingMonth {
                try stageReplaceMonth(rows, periodMonth: periodMonth, context: context, fetching: store)
            } else {
                try stageApply(rows, periodMonth: periodMonth, context: context, fetching: store, now: now)
            }
            return try PortfolioSnapshotService.stageCapture(
                periodMonth,
                homeCurrency: homeCurrency,
                note: note,
                historicalRates: rates,
                context: context,
                fetching: store,
                now: now
            )
        }
    }

    /// Upserts every non-nil row for `periodMonth`. Behaves atomically: on
    /// failure we discard the staged changes by rolling back to the last
    /// saved state.
    static func apply(
        _ rows: [Row],
        periodMonth: Date,
        context: ModelContext
    ) throws {
        guard rows.contains(where: { $0.amount != nil }) else { return }
        try saveOrRollback(context) {
            try stageApply(rows, periodMonth: periodMonth, context: context, fetching: context)
        }
    }

    /// Replaces all per-holding snapshots inside the month containing
    /// `periodMonth` for the holdings present in `rows`.
    ///
    /// Used when editing an existing `PortfolioSnapshot`: the editor is
    /// rewriting the captured state for that month, so older day-granular
    /// rows in the same month must not survive and win the "latest value"
    /// lookup during recapture.
    static func replaceMonth(
        _ rows: [Row],
        periodMonth: Date,
        context: ModelContext
    ) throws {
        guard !rows.isEmpty else { return }
        try saveOrRollback(context) {
            try stageReplaceMonth(rows, periodMonth: periodMonth, context: context, fetching: context)
        }
    }

    // MARK: - Staging

    private static func stageApply(
        _ rows: [Row],
        periodMonth: Date,
        context: ModelContext,
        fetching store: any ModelFetching,
        now: Date = .now
    ) throws {
        let nonEmpty = rows.filter { $0.amount != nil }
        guard !nonEmpty.isEmpty else { return }

        // Build a quick lookup so we don't refetch for every row.
        let byId = try holdingsById(in: store)
        for row in nonEmpty {
            guard let holding = byId[row.holdingId], let amount = row.amount else { continue }
            _ = SnapshotService.upsert(
                amount: amount,
                periodMonth: periodMonth,
                for: holding,
                context: context,
                now: now
            )
        }
    }

    private static func stageReplaceMonth(
        _ rows: [Row],
        periodMonth: Date,
        context: ModelContext,
        fetching store: any ModelFetching
    ) throws {
        guard !rows.isEmpty else { return }

        let byId = try holdingsById(in: store)
        let holdingIds = Set(rows.map(\.holdingId))
        let monthStart = Snapshot.normalize(periodMonth)
        let monthEnd = Snapshot.nextMonthStart(after: monthStart)

        let descriptor = FetchDescriptor<Snapshot>(
            predicate: #Predicate { $0.periodMonth >= monthStart && $0.periodMonth < monthEnd }
        )
        for snapshot in try store.fetch(descriptor) {
            guard let holdingId = snapshot.holding?.id, holdingIds.contains(holdingId) else { continue }
            context.delete(snapshot)
        }

        let day = Snapshot.normalizeDay(periodMonth)
        for row in rows {
            guard let holding = byId[row.holdingId], let amount = row.amount else { continue }
            let snapshot = Snapshot(periodMonth: day, amount: amount, holding: holding)
            context.insert(snapshot)
        }
    }

    private static func holdingsById(in store: any ModelFetching) throws -> [UUID: Holding] {
        let holdings = try store.fetch(FetchDescriptor<Holding>())
        return Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0) })
    }

    /// Runs `stage` and saves; on any failure discards everything staged
    /// since the last save.
    private static func saveOrRollback<T>(_ context: ModelContext, _ stage: () throws -> T) throws -> T {
        do {
            let result = try stage()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}

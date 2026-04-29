import Foundation
import SwiftData

/// Atomic batch-upsert for the spreadsheet-style entry screen.
@MainActor
public enum BatchUpsertService {
    /// A single pending edit from the grid.
    public struct Row: Sendable {
        public let holdingId: UUID
        public let amount: Decimal?  // nil means "leave blank — no snapshot"

        public init(holdingId: UUID, amount: Decimal?) {
            self.holdingId = holdingId
            self.amount = amount
        }
    }

    /// Upserts every non-nil row for `periodMonth`. Behaves atomically: on
    /// failure we discard the staged changes by rolling back to the last
    /// saved state.
    public static func apply(
        _ rows: [Row],
        periodMonth: Date,
        context: ModelContext
    ) throws {
        let nonEmpty = rows.filter { $0.amount != nil }
        guard !nonEmpty.isEmpty else { return }

        // Build a quick lookup so we don't refetch for every row.
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        let byId = Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0) })

        for row in nonEmpty {
            guard let holding = byId[row.holdingId], let amount = row.amount else { continue }
            _ = SnapshotService.upsert(
                amount: amount,
                periodMonth: periodMonth,
                for: holding,
                context: context
            )
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Replaces all per-holding snapshots inside the month containing
    /// `periodMonth` for the holdings present in `rows`.
    ///
    /// Used when editing an existing `PortfolioSnapshot`: the editor is
    /// rewriting the captured state for that month, so older day-granular
    /// rows in the same month must not survive and win the "latest value"
    /// lookup during recapture.
    public static func replaceMonth(
        _ rows: [Row],
        periodMonth: Date,
        context: ModelContext
    ) throws {
        guard !rows.isEmpty else { return }

        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        let byId = Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0) })
        let holdingIds = Set(rows.map(\.holdingId))
        let monthStart = Snapshot.normalize(periodMonth)
        let monthEnd = nextMonthStart(after: monthStart)

        let descriptor = FetchDescriptor<Snapshot>(
            predicate: #Predicate { $0.periodMonth >= monthStart && $0.periodMonth < monthEnd }
        )
        let monthlySnapshots = (try? context.fetch(descriptor)) ?? []
        for snapshot in monthlySnapshots {
            guard let holdingId = snapshot.holding?.id, holdingIds.contains(holdingId) else { continue }
            context.delete(snapshot)
        }

        let day = Snapshot.normalizeDay(periodMonth)
        for row in rows {
            guard let holding = byId[row.holdingId], let amount = row.amount else { continue }
            let snapshot = Snapshot(periodMonth: day, amount: amount, holding: holding)
            context.insert(snapshot)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func nextMonthStart(after monthStart: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }
}

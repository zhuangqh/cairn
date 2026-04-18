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
}

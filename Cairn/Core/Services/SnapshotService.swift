import Foundation
import SwiftData

/// Business rules for `Snapshot`.
///
/// Snapshots are day-granular — a given `(holding, day)` pair must be
/// unique. Uniqueness is enforced here instead of via a
/// CloudKit-incompatible unique attribute.
public enum SnapshotService {
    /// Upsert a snapshot for `(holding, day)`:
    /// - If one already exists for that day: update its `amount` and `recordedAt`.
    /// - Otherwise: insert a new snapshot on that day.
    ///
    /// Returns the effective snapshot.
    @MainActor
    @discardableResult
    public static func upsert(
        amount: Decimal,
        periodMonth: Date,
        for holding: Holding,
        context: ModelContext,
        now: Date = .now
    ) -> Snapshot {
        let day = Snapshot.normalizeDay(periodMonth)
        if let existing = (holding.snapshots ?? []).first(where: { $0.periodMonth == day }) {
            existing.amount = amount
            existing.recordedAt = now
            return existing
        }
        let snapshot = Snapshot(periodMonth: day, amount: amount, holding: holding, recordedAt: now)
        context.insert(snapshot)
        return snapshot
    }

    /// Returns the snapshot for the given day if one exists, else nil.
    public static func snapshot(
        for holding: Holding,
        in periodMonth: Date
    ) -> Snapshot? {
        let day = Snapshot.normalizeDay(periodMonth)
        return (holding.snapshots ?? []).first { $0.periodMonth == day }
    }
}

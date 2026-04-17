import Foundation
import SwiftData

/// Business rules for `Snapshot`.
///
/// Snapshots have monthly granularity — a given `(holding, periodMonth)` pair
/// must be unique. This is enforced here instead of via a CloudKit-incompatible
/// unique attribute.
public enum SnapshotService {
    /// Upsert a snapshot for `(holding, periodMonth)`:
    /// - If one already exists: update its `amount` and `recordedAt`.
    /// - Otherwise: insert a new snapshot.
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
        let month = Snapshot.normalize(periodMonth)
        if let existing = (holding.snapshots ?? []).first(where: { $0.periodMonth == month }) {
            existing.amount = amount
            existing.recordedAt = now
            return existing
        }
        let snapshot = Snapshot(periodMonth: month, amount: amount, holding: holding, recordedAt: now)
        context.insert(snapshot)
        return snapshot
    }

    /// Returns the snapshot for the given month if one exists, else nil.
    public static func snapshot(
        for holding: Holding,
        in periodMonth: Date
    ) -> Snapshot? {
        let month = Snapshot.normalize(periodMonth)
        return (holding.snapshots ?? []).first { $0.periodMonth == month }
    }
}

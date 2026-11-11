import Foundation

/// Values used to seed `BatchEntryView` when editing a captured snapshot.
/// Derived from the stored entries and rates; adds no stored properties.
extension PortfolioSnapshot {
    /// Captured rates rebuilt as `quote → rate` (matching Frankfurter's
    /// `1 home == rate × quote` convention) so the editor reuses the
    /// snapshot's historical rates instead of refetching live data.
    var lockedRatesForEdit: [String: Decimal] {
        var map: [String: Decimal] = [:]
        for rate in rates where rate.base == homeCurrency {
            map[rate.quote] = rate.rate
        }
        return map
    }

    /// Captured per-holding amounts keyed by `holdingId`, used to seed
    /// the editor with the snapshot's recorded values rather than the
    /// previous month's. Entries whose holding has since been deleted
    /// (no `holdingId`) are skipped — the row simply won't appear.
    var lockedBaselineForEdit: [UUID: Decimal] {
        var map: [UUID: Decimal] = [:]
        for entry in entries {
            guard let holdingId = entry.holdingId else { continue }
            map[holdingId] = entry.amount
        }
        return map
    }
}

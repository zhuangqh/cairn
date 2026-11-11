import SwiftUI

/// Snapshot-to-snapshot comparison: per-member grouping with row deltas and
/// the display rows for the `PortfolioChangeBreakdown` shown by
/// `PortfolioSnapshotDetailView`.
extension PortfolioSnapshotDetailView {
    /// Pairs each current entry with its prior counterpart (matched by
    /// `holdingId`), grouped and sorted for stable display. `entries` and
    /// `priorEntries` are `snapshot.entries` / `previous?.entries`, decoded
    /// once per render by the caller.
    func memberGroups(
        entries currentEntries: [PortfolioSnapshot.Entry],
        priorEntries: [PortfolioSnapshot.Entry]?
    ) -> [MemberGroup] {
        let priorByHolding = priorEntries.map(PortfolioChangeBreakdown.entriesByHolding) ?? [:]
        let kindByHolding = accountKindByHolding(for: currentEntries)

        let grouped = Dictionary(grouping: currentEntries, by: { $0.memberName })
        return grouped.keys.sorted().map { member in
            let entries = (grouped[member] ?? [])
                .sorted { lhs, rhs in
                    if lhs.accountName == rhs.accountName {
                        return lhs.currency < rhs.currency
                    }
                    return lhs.accountName < rhs.accountName
                }
                .map { entry -> EntryRow in
                    let prior = entry.holdingId.flatMap { priorByHolding[$0] }
                    // Per-row delta is computed in the holding's *native*
                    // currency so the displayed value matches the row's
                    // primary number. Mismatched currencies (a holding
                    // that switched currency between snapshots) are not
                    // comparable on a single line, so we suppress the delta.
                    let delta: Decimal? = {
                        guard let prior, prior.currency == entry.currency else { return nil }
                        return entry.amount - prior.amount
                    }()
                    // Prefer the kind captured in the snapshot itself
                    // (added later) — relying on live `holding.account`
                    // traversal is unreliable on iOS when relationships
                    // are lazily loaded, which can flip the icon to the
                    // `.cash` fallback for non-cash kinds.
                    let kind = entry.accountKind
                        ?? entry.holdingId.flatMap { kindByHolding[$0] }
                        ?? .cash
                    return EntryRow(
                        current: entry,
                        prior: prior,
                        delta: delta,
                        accountKind: kind
                    )
                }
            let total = entries
                .compactMap { $0.current.convertedAmount }
                .reduce(Decimal(0), +)
            let memberDelta: Decimal? = {
                guard priorEntries != nil else { return nil }
                let now = entries.compactMap { $0.current.convertedAmount }.reduce(Decimal(0), +)
                let was = entries.compactMap { $0.prior?.convertedAmount }.reduce(Decimal(0), +)
                // Only meaningful when at least one entry resolves both sides.
                let hasAnyPrior = entries.contains { $0.prior != nil }
                return hasAnyPrior ? (now - was) : nil
            }()
            return MemberGroup(
                member: member,
                entries: entries,
                total: total,
                delta: memberDelta
            )
        }
    }

    struct MemberGroup {
        let member: String
        let entries: [EntryRow]
        let total: Decimal
        let delta: Decimal?
    }

    struct EntryRow {
        let current: PortfolioSnapshot.Entry
        let prior: PortfolioSnapshot.Entry?
        let delta: Decimal?
        let accountKind: AccountKind
    }

    struct TotalDelta {
        let amount: Decimal
        let percent: Double?
        let previousMonth: Date
    }

    var totalDelta: TotalDelta? {
        guard let previous else { return nil }
        let amount = snapshot.totalAmount - previous.totalAmount
        let percent = NetWorthCalculator.percentChange(
            current: snapshot.totalAmount,
            previous: previous.totalAmount
        )
        return TotalDelta(amount: amount, percent: percent, previousMonth: previous.periodMonth)
    }
}

extension PortfolioSnapshotDetailView {
    struct BreakdownRow: Identifiable {
        let id: String
        let titleKey: LocalizedStringKey
        let subtitleKey: LocalizedStringKey
        let amount: Decimal
    }
}

extension PortfolioChangeBreakdown {
    /// FX and manual-update rows shown in the change card; zero-valued
    /// components are omitted.
    var displayRows: [PortfolioSnapshotDetailView.BreakdownRow] {
        var rows: [PortfolioSnapshotDetailView.BreakdownRow] = []
        if fx != 0 {
            rows.append(PortfolioSnapshotDetailView.BreakdownRow(
                id: "fx",
                titleKey: "portfolioSnapshot.detail.change.fx",
                subtitleKey: "portfolioSnapshot.detail.change.fx.hint",
                amount: fx
            ))
        }
        if manualNet != 0 {
            rows.append(PortfolioSnapshotDetailView.BreakdownRow(
                id: "manual",
                titleKey: "portfolioSnapshot.detail.change.manual",
                subtitleKey: "portfolioSnapshot.detail.change.manual.hint",
                amount: manualNet
            ))
        }
        return rows
    }
}

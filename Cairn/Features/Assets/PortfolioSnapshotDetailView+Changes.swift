import SwiftUI

/// Snapshot-to-snapshot comparison: per-member grouping with row deltas and
/// the market / FX / manual-update decomposition shown by
/// `PortfolioSnapshotDetailView`.
extension PortfolioSnapshotDetailView {
    /// Pairs each current entry with its prior counterpart (matched by
    /// `holdingId`), grouped and sorted for stable display.
    var memberGroups: [MemberGroup] {
        let priorByHolding: [UUID: PortfolioSnapshot.Entry] = {
            guard let previous else { return [:] }
            var map: [UUID: PortfolioSnapshot.Entry] = [:]
            for entry in previous.entries {
                if let id = entry.holdingId { map[id] = entry }
            }
            return map
        }()
        let kindByHolding = accountKindByHolding

        let grouped = Dictionary(grouping: snapshot.entries, by: { $0.memberName })
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
                guard previous != nil else { return nil }
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
        let percent: Double? = {
            guard previous.totalAmount != 0 else { return nil }
            let pct = (snapshot.totalAmount - previous.totalAmount) / previous.totalAmount
            return NSDecimalNumber(decimal: pct).doubleValue
        }()
        return TotalDelta(amount: amount, percent: percent, previousMonth: previous.periodMonth)
    }

    // MARK: - Change decomposition

    /// Splits `totalNew - totalOld` into market movement, FX impact, and
    /// manual updates (added / removed holdings).
    ///
    /// For a matched holding (same `holdingId`) priced in a foreign
    /// currency we decompose:
    ///   `Δhome = (amountNew - amountOld) / rateNew + amountOld × (1/rateNew - 1/rateOld)`
    /// where the *effective* rate is recovered from each snapshot's
    /// stored entry as `rate = amount / convertedAmount` so we don't
    /// depend on the rate-storage convention. The first term is "market
    /// movement", the second is "FX impact". Home-currency holdings have
    /// no FX component.
    ///
    /// Holdings present only in one side count as "manual updates"
    /// (added or removed). When `convertedAmount` is missing we fall
    /// back to attributing the whole delta to market movement.
    var breakdown: ChangeBreakdown? {
        guard let previous else { return nil }
        var market: Decimal = 0
        var fx: Decimal = 0
        var manualAdded: Decimal = 0
        var manualRemoved: Decimal = 0
        var fxRateChanges: [FXRateChange] = []
        var seenFX: Set<String> = []

        let priorByHolding: [UUID: PortfolioSnapshot.Entry] = {
            var map: [UUID: PortfolioSnapshot.Entry] = [:]
            for entry in previous.entries {
                if let id = entry.holdingId { map[id] = entry }
            }
            return map
        }()
        var priorRemaining = priorByHolding

        for entry in snapshot.entries {
            let prior = entry.holdingId.flatMap { priorByHolding[$0] }
            if let prior, prior.currency == entry.currency {
                if let id = entry.holdingId { priorRemaining.removeValue(forKey: id) }
                let homeNow = entry.convertedAmount
                let homeWas = prior.convertedAmount

                if entry.currency == snapshot.homeCurrency {
                    // Home currency: 100% market.
                    if let homeNow, let homeWas {
                        market += (homeNow - homeWas)
                    }
                } else if let homeNow, let homeWas,
                          entry.amount != 0, prior.amount != 0,
                          homeNow != 0, homeWas != 0 {
                    // Effective rates have units `foreign / home`.
                    let rateNew = entry.amount / homeNow
                    let rateOld = prior.amount / homeWas
                    let marketComponent = (entry.amount - prior.amount) / rateNew
                    let fxComponent = prior.amount * (1 / rateNew - 1 / rateOld)
                    market += marketComponent
                    fx += fxComponent
                    if !seenFX.contains(entry.currency), rateNew != rateOld {
                        seenFX.insert(entry.currency)
                        fxRateChanges.append(FXRateChange(
                            currency: entry.currency,
                            oldRate: rateOld == 0 ? 0 : 1 / rateOld,
                            newRate: rateNew == 0 ? 0 : 1 / rateNew
                        ))
                    }
                } else if let homeNow, let homeWas {
                    // Missing data — attribute to market.
                    market += (homeNow - homeWas)
                }
            } else {
                // Added (no prior, or currency changed).
                if let prior {
                    // Currency changed: treat as remove + add.
                    if let id = entry.holdingId { priorRemaining.removeValue(forKey: id) }
                    if let homeWas = prior.convertedAmount { manualRemoved -= homeWas }
                }
                if let homeNow = entry.convertedAmount {
                    manualAdded += homeNow
                }
            }
        }

        // Anything left in `priorRemaining` was removed this period.
        for (_, prior) in priorRemaining {
            if let homeWas = prior.convertedAmount {
                manualRemoved -= homeWas
            }
        }

        return ChangeBreakdown(
            market: market,
            fx: fx,
            manualAdded: manualAdded,
            manualRemoved: manualRemoved,
            fxRateChanges: fxRateChanges.sorted { $0.currency < $1.currency }
        )
    }

    struct FXRateChange: Identifiable {
        var id: String { currency }
        let currency: String
        let oldRate: Decimal
        let newRate: Decimal
    }

    struct ChangeBreakdown {
        let market: Decimal
        let fx: Decimal
        let manualAdded: Decimal
        let manualRemoved: Decimal
        let fxRateChanges: [FXRateChange]

        var manualNet: Decimal { manualAdded + manualRemoved }
        var hasContent: Bool {
            fx != 0 || manualNet != 0
        }

        var displayRows: [BreakdownRow] {
            var rows: [BreakdownRow] = []
            if fx != 0 {
                rows.append(BreakdownRow(
                    id: "fx",
                    titleKey: "portfolioSnapshot.detail.change.fx",
                    subtitleKey: "portfolioSnapshot.detail.change.fx.hint",
                    amount: fx
                ))
            }
            if manualNet != 0 {
                rows.append(BreakdownRow(
                    id: "manual",
                    titleKey: "portfolioSnapshot.detail.change.manual",
                    subtitleKey: "portfolioSnapshot.detail.change.manual.hint",
                    amount: manualNet
                ))
            }
            return rows
        }
    }

    struct BreakdownRow: Identifiable {
        let id: String
        let titleKey: LocalizedStringKey
        let subtitleKey: LocalizedStringKey
        let amount: Decimal
    }
}

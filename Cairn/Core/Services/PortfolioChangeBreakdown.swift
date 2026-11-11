import Foundation

/// Splits the change between two portfolio snapshots into market movement,
/// FX impact, and manual updates (added / removed holdings).
struct PortfolioChangeBreakdown {
    struct FXRateChange: Identifiable {
        var id: String { currency }
        let currency: String
        let oldRate: Decimal
        let newRate: Decimal
    }

    let market: Decimal
    let fx: Decimal
    let manualAdded: Decimal
    let manualRemoved: Decimal
    let fxRateChanges: [FXRateChange]

    var manualNet: Decimal { manualAdded + manualRemoved }
    var hasContent: Bool {
        fx != 0 || manualNet != 0
    }

    /// `entries` keyed by `holdingId`; entries without one are skipped and a
    /// repeated id keeps the last entry.
    static func entriesByHolding(_ entries: [PortfolioSnapshot.Entry]) -> [UUID: PortfolioSnapshot.Entry] {
        var map: [UUID: PortfolioSnapshot.Entry] = [:]
        for entry in entries {
            if let id = entry.holdingId { map[id] = entry }
        }
        return map
    }

    /// Decomposes `current` against `prior`; `nil` when there is no prior
    /// snapshot (`prior == nil`).
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
    /// (added or removed); a holding whose currency changed counts as
    /// removed + added. When `convertedAmount` is missing we fall back to
    /// attributing the whole delta to market movement.
    static func compute(
        current: [PortfolioSnapshot.Entry],
        prior priorEntries: [PortfolioSnapshot.Entry]?,
        homeCurrency: String
    ) -> PortfolioChangeBreakdown? {
        guard let priorEntries else { return nil }
        var tally = Tally()
        let priorByHolding = entriesByHolding(priorEntries)
        var priorRemaining = priorByHolding

        for entry in current {
            let prior = entry.holdingId.flatMap { priorByHolding[$0] }
            if prior != nil, let id = entry.holdingId { priorRemaining.removeValue(forKey: id) }
            if let prior, prior.currency == entry.currency {
                tally.addMatched(entry, prior: prior, homeCurrency: homeCurrency)
            } else {
                // Added (no prior, or currency changed: remove + add).
                if let prior { tally.addRemoved(prior) }
                if let homeNow = entry.convertedAmount {
                    tally.manualAdded += homeNow
                }
            }
        }

        // Anything left in `priorRemaining` was removed this period.
        for (_, prior) in priorRemaining {
            tally.addRemoved(prior)
        }

        return PortfolioChangeBreakdown(
            market: tally.market,
            fx: tally.fx,
            manualAdded: tally.manualAdded,
            manualRemoved: tally.manualRemoved,
            fxRateChanges: tally.fxRateChanges.sorted { $0.currency < $1.currency }
        )
    }

    /// Running sums while walking the current entries.
    private struct Tally {
        var market: Decimal = 0
        var fx: Decimal = 0
        var manualAdded: Decimal = 0
        var manualRemoved: Decimal = 0
        var fxRateChanges: [FXRateChange] = []
        var seenFX: Set<String> = []

        /// A holding present on both sides in the same currency.
        mutating func addMatched(
            _ entry: PortfolioSnapshot.Entry,
            prior: PortfolioSnapshot.Entry,
            homeCurrency: String
        ) {
            let homeNow = entry.convertedAmount
            let homeWas = prior.convertedAmount

            if entry.currency == homeCurrency {
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
        }

        mutating func addRemoved(_ prior: PortfolioSnapshot.Entry) {
            if let homeWas = prior.convertedAmount {
                manualRemoved -= homeWas
            }
        }
    }
}

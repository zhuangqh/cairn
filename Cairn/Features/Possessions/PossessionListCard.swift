import SwiftUI

/// A category card (or the trailing Sold card) in the list below the hero.
struct PossessionListCard: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    let accessory: String
    let possessions: [Possession]
    let dimmed: Bool

    #if os(macOS)
    /// Greedy two-column split by row count (+1 for each card header),
    /// preserving category order within each column.
    static func balancedColumns(_ cards: [PossessionListCard]) -> ([PossessionListCard], [PossessionListCard]) {
        var left: [PossessionListCard] = []
        var right: [PossessionListCard] = []
        var leftWeight = 0
        var rightWeight = 0
        for card in cards {
            let weight = card.possessions.count + 1
            if leftWeight <= rightWeight {
                left.append(card)
                leftWeight += weight
            } else {
                right.append(card)
                rightWeight += weight
            }
        }
        return (left, right)
    }
    #endif
}

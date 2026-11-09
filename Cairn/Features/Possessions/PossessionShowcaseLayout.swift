import Foundation

/// Arrangement rules for the Possessions showcase: one shelf per category,
/// most expensive first. Every figure is drawn at the same size.
enum PossessionShowcaseLayout {
    struct Shelf: Identifiable {
        let category: PossessionCategory
        let items: [Possession]
        var id: PossessionCategory { category }
    }

    /// Shelves in category order, skipping empty categories. `homeCost`
    /// returns the purchase price in the home currency, or `nil` when no
    /// rate is available; those items sort after every priced item.
    static func shelves(
        byCategory: [PossessionCategory: [Possession]],
        homeCost: (Possession) -> Decimal?
    ) -> [Shelf] {
        PossessionCategory.allCases.compactMap { category in
            guard let possessions = byCategory[category], !possessions.isEmpty else { return nil }
            let sorted = possessions
                .map { (possession: $0, cost: homeCost($0)) }
                .sorted { lhs, rhs in
                    switch (lhs.cost, rhs.cost) {
                    case let (left?, right?): return left > right
                    case (.some, nil): return true
                    default: return false
                    }
                }
                .map(\.possession)
            return Shelf(category: category, items: sorted)
        }
    }
}

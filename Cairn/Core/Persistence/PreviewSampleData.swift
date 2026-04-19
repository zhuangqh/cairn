import Foundation
import SwiftData

/// Seeded in-memory data for SwiftUI previews & manual debugging.
///
/// `PersistenceController.previewContainer()` returns an empty store; this
/// helper layers a realistic graph on top so feature previews can exercise
/// non-trivial states (multiple members, accounts across kinds, multi-currency
/// holdings with several months of snapshots, FX rates, and a captured
/// portfolio snapshot) without each call site re-building the same fixtures.
@MainActor
public enum PreviewSampleData {

    // MARK: - Public entry points

    /// Fresh in-memory container pre-populated with the demo graph. A new
    /// container is returned on every call so individual previews cannot
    /// pollute each other's state.
    public static func container(homeCurrency: String = "USD") -> ModelContainer {
        seededContainer(homeCurrency: homeCurrency).container
    }

    /// Same as `container(_:)`, but also returns the seeded references so
    /// previews can pass specific members / accounts / holdings into the view
    /// under inspection without re-fetching them.
    public static func seededContainer(homeCurrency: String = "USD") -> (container: ModelContainer, seed: Seeded) {
        let container = PersistenceController.previewContainer()
        let seed = populate(container.mainContext, homeCurrency: homeCurrency)
        try? container.mainContext.save()
        return (container, seed)
    }

    /// Empty in-memory container — for previewing empty / zero-state UI.
    public static func emptyContainer() -> ModelContainer {
        PersistenceController.previewContainer()
    }

    // MARK: - Seeded references

    public struct Seeded {
        public let alice: Member
        public let bob: Member
        public let checking: Account
        public let brokerage: Account
        public let apartment: Account
        public let bobCash: Account
        public let emptyAccount: Account
        public let checkingUSD: Holding
        public let checkingEUR: Holding
        public let brokerageUSD: Holding
        public let apartmentCNY: Holding
        public let bobCNY: Holding
        public let latestPortfolioSnapshot: PortfolioSnapshot
    }

    // MARK: - Seeding

    @discardableResult
    public static func populate(
        _ context: ModelContext,
        homeCurrency: String = "USD"
    ) -> Seeded {
        // Members --------------------------------------------------------
        let alice = Member(name: "Alice")
        let bob = Member(name: "Bob")
        context.insert(alice)
        context.insert(bob)

        // Accounts — mix of kinds so the dashboard donut has variety ----
        let checking = Account(name: "Checking", kind: .cash, member: alice)
        let brokerage = Account(name: "Brokerage", kind: .stock, member: alice)
        let apartment = Account(name: "Apartment", kind: .realEstate, member: alice)
        let bobCash = Account(name: "Savings", kind: .cash, member: bob)
        // Keeps a zero-state path reachable from MemberDetailView previews.
        let emptyAccount = Account(name: "Laptop", kind: .device, member: bob)
        [checking, brokerage, apartment, bobCash, emptyAccount].forEach(context.insert)

        // Holdings — multi-currency so FX edge cases are covered --------
        let checkingUSD = Holding(currency: "USD", label: nil, account: checking)
        let checkingEUR = Holding(currency: "EUR", label: "Travel", account: checking)
        let brokerageUSD = Holding(currency: "USD", label: "Index funds", account: brokerage)
        let apartmentCNY = Holding(currency: "CNY", label: "Shanghai", account: apartment)
        let bobCNY = Holding(currency: "CNY", label: nil, account: bobCash)
        [checkingUSD, checkingEUR, brokerageUSD, apartmentCNY, bobCNY].forEach(context.insert)

        // Snapshots — 6 months of steady growth per holding -------------
        let months = recentMonths(6)
        let trajectories: [(Holding, Decimal, Decimal)] = [
            (checkingUSD, 12_000, 300),
            (checkingEUR, 3_500, 120),
            (brokerageUSD, 58_000, 1_400),
            (apartmentCNY, 3_200_000, 8_000),
            (bobCNY, 120_000, 2_500),
        ]
        for (holding, start, step) in trajectories {
            for (offset, month) in months.enumerated() {
                let amount = start + step * Decimal(offset)
                context.insert(Snapshot(periodMonth: month, amount: amount, holding: holding))
            }
        }

        // FX rates — both directions for the common pairs ---------------
        let today = Date()
        let rates: [(String, String, Decimal)] = [
            ("EUR", "USD", 1.08),
            ("CNY", "USD", 0.14),
            ("USD", "EUR", 0.93),
            ("USD", "CNY", 7.15),
        ]
        for (base, quote, rate) in rates {
            context.insert(FXRate(base: base, quote: quote, rate: rate, date: today))
        }

        // One captured portfolio snapshot (latest month) ----------------
        let latestMonth = months.last ?? today
        let entries: [PortfolioSnapshot.Entry] = [
            .init(
                holdingId: checkingUSD.id,
                memberName: alice.name,
                accountName: checking.name,
                holdingLabel: nil,
                currency: "USD",
                amount: 13_500,
                convertedAmount: 13_500
            ),
            .init(
                holdingId: brokerageUSD.id,
                memberName: alice.name,
                accountName: brokerage.name,
                holdingLabel: "Index funds",
                currency: "USD",
                amount: 65_000,
                convertedAmount: 65_000
            ),
            .init(
                holdingId: apartmentCNY.id,
                memberName: alice.name,
                accountName: apartment.name,
                holdingLabel: "Shanghai",
                currency: "CNY",
                amount: 3_240_000,
                convertedAmount: 453_600
            ),
            .init(
                holdingId: bobCNY.id,
                memberName: bob.name,
                accountName: bobCash.name,
                holdingLabel: nil,
                currency: "CNY",
                amount: 132_500,
                convertedAmount: 18_550
            )
        ]
        let portfolioRates: [PortfolioSnapshot.Rate] = [
            .init(base: "EUR", quote: homeCurrency, rate: 1.08),
            .init(base: "CNY", quote: homeCurrency, rate: 0.14)
        ]
        let total = entries.compactMap(\.convertedAmount).reduce(Decimal(0), +)
        let portfolio = PortfolioSnapshot(
            periodMonth: latestMonth,
            homeCurrency: homeCurrency,
            totalAmount: total,
            entries: entries,
            rates: portfolioRates,
            note: "Preview sample"
        )
        context.insert(portfolio)

        return Seeded(
            alice: alice,
            bob: bob,
            checking: checking,
            brokerage: brokerage,
            apartment: apartment,
            bobCash: bobCash,
            emptyAccount: emptyAccount,
            checkingUSD: checkingUSD,
            checkingEUR: checkingEUR,
            brokerageUSD: brokerageUSD,
            apartmentCNY: apartmentCNY,
            bobCNY: bobCNY,
            latestPortfolioSnapshot: portfolio
        )
    }

    // MARK: - Helpers

    private static func recentMonths(_ count: Int) -> [Date] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = Snapshot.normalize(.now)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: now)
        }
    }
}

#if DEBUG
/// Ensures `@AppStorage`-backed onboarding / home-currency flags are primed
/// for previews that render the full app shell. Call once from a preview
/// closure before instantiating the view.
@MainActor
public enum PreviewDefaults {
    public static func primeOnboarded(homeCurrency: String = "USD") {
        UserDefaults.standard.set(true, forKey: AppSettingsKeys.onboardingCompleted)
        UserDefaults.standard.set(homeCurrency, forKey: AppSettingsKeys.homeCurrency)
    }
}
#endif

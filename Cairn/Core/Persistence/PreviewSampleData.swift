import Foundation
import SwiftData

/// Seeded in-memory data for SwiftUI previews & manual debugging.
///
/// `PersistenceController.previewContainer()` returns an empty store; this
/// helper layers a realistic graph on top so feature previews can exercise
/// non-trivial states (multiple members, accounts across kinds, multi-currency
/// holdings with several months of snapshots, FX rates, and a captured
/// portfolio snapshot, and in DEBUG builds possessions with bundled photos)
/// without each call site re-building the same fixtures.
@MainActor
enum PreviewSampleData {

    // MARK: - Public entry points

    /// Fresh in-memory container pre-populated with the demo graph. A new
    /// container is returned on every call so individual previews cannot
    /// pollute each other's state.
    static func container(homeCurrency: String = "USD") -> ModelContainer {
        seededContainer(homeCurrency: homeCurrency).container
    }

    /// Same as `container(_:)`, but also returns the seeded references so
    /// previews can pass specific members / accounts / holdings into the view
    /// under inspection without re-fetching them.
    static func seededContainer(homeCurrency: String = "USD") -> (container: ModelContainer, seed: Seeded) {
        let container = PersistenceController.previewContainer()
        let seed = populate(container.mainContext, homeCurrency: homeCurrency)
        try? container.mainContext.save()
        return (container, seed)
    }

    /// Empty in-memory container — for previewing empty / zero-state UI.
    static func emptyContainer() -> ModelContainer {
        PersistenceController.previewContainer()
    }

    #if DEBUG
    /// In-memory container restored from a Cairn backup file, used by the
    /// `-CairnMockData <path>` visual-review launch with the shared mock
    /// dataset (`example/cairn-mock-data.json`). The user's store is never
    /// opened; a missing or invalid file stops the debug launch.
    static func mockContainer(contentsOf url: URL) -> ModelContainer {
        let container = PersistenceController.previewContainer()
        do {
            let data = try Data(contentsOf: url)
            try BackupService.restoreReplacing(from: data, context: container.mainContext)
        } catch {
            fatalError("Could not load mock data from \(url.path): \(error)")
        }
        return container
    }
    #endif

    // MARK: - Seeded references

    struct Seeded {
        let alice: Member
        let bob: Member
        let checking: Account
        let brokerage: Account
        let apartment: Account
        let bobCash: Account
        let emptyAccount: Account
        let checkingUSD: Holding
        let checkingEUR: Holding
        let brokerageUSD: Holding
        let apartmentCNY: Holding
        let bobCNY: Holding
        let latestPortfolioSnapshot: PortfolioSnapshot
    }

    // MARK: - Seeding

    @discardableResult
    static func populate(
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
        insertSnapshots(context, months: months, trajectories: [
            Trajectory(holding: checkingUSD, start: 12_000, step: 300),
            Trajectory(holding: checkingEUR, start: 3_500, step: 120),
            Trajectory(holding: brokerageUSD, start: 58_000, step: 1_400),
            Trajectory(holding: apartmentCNY, start: 3_200_000, step: 8_000),
            Trajectory(holding: bobCNY, start: 120_000, step: 2_500)
        ])

        // FX rates — both directions for the common pairs ---------------
        let today = Date()
        insertFXRates(context, date: today)

        // One captured portfolio snapshot (latest month) ----------------
        let portfolio = latestPortfolioSnapshot(
            entries: [
                portfolioEntry(checkingUSD, amount: 13_500, convertedAmount: 13_500),
                portfolioEntry(brokerageUSD, amount: 65_000, convertedAmount: 65_000),
                portfolioEntry(apartmentCNY, amount: 3_240_000, convertedAmount: 453_600),
                portfolioEntry(bobCNY, amount: 132_500, convertedAmount: 18_550)
            ],
            periodMonth: months.last ?? today,
            homeCurrency: homeCurrency
        )
        context.insert(portfolio)

        #if DEBUG
        populatePossessions(context, alice: alice, bob: bob)
        #endif

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

    /// Linear monthly growth for one holding's sample snapshots.
    private struct Trajectory {
        let holding: Holding
        let start: Decimal
        let step: Decimal
    }

    private struct SampleRate {
        let base: String
        let quote: String
        let rate: Decimal
    }

    private static func insertSnapshots(
        _ context: ModelContext,
        months: [Date],
        trajectories: [Trajectory]
    ) {
        for trajectory in trajectories {
            for (offset, month) in months.enumerated() {
                let amount = trajectory.start + trajectory.step * Decimal(offset)
                context.insert(Snapshot(periodMonth: month, amount: amount, holding: trajectory.holding))
            }
        }
    }

    private static func insertFXRates(_ context: ModelContext, date: Date) {
        let rates = [
            SampleRate(base: "EUR", quote: "USD", rate: 1.08),
            SampleRate(base: "CNY", quote: "USD", rate: 0.14),
            SampleRate(base: "USD", quote: "EUR", rate: 0.93),
            SampleRate(base: "USD", quote: "CNY", rate: 7.15)
        ]
        for sample in rates {
            context.insert(FXRate(base: sample.base, quote: sample.quote, rate: sample.rate, date: date))
        }
    }

    /// Captured entry for `holding`, reading its member / account names,
    /// label, and currency from the seeded relationships.
    private static func portfolioEntry(
        _ holding: Holding,
        amount: Decimal,
        convertedAmount: Decimal
    ) -> PortfolioSnapshot.Entry {
        .init(
            holdingId: holding.id,
            memberName: holding.account?.member?.name ?? "",
            accountName: holding.account?.name ?? "",
            holdingLabel: holding.label,
            currency: holding.currency,
            amount: amount,
            convertedAmount: convertedAmount
        )
    }

    private static func latestPortfolioSnapshot(
        entries: [PortfolioSnapshot.Entry],
        periodMonth: Date,
        homeCurrency: String
    ) -> PortfolioSnapshot {
        let portfolioRates: [PortfolioSnapshot.Rate] = [
            .init(base: "EUR", quote: homeCurrency, rate: 1.08),
            .init(base: "CNY", quote: homeCurrency, rate: 0.14)
        ]
        let total = entries.compactMap(\.convertedAmount).reduce(Decimal(0), +)
        return PortfolioSnapshot(
            periodMonth: periodMonth,
            homeCurrency: homeCurrency,
            totalAmount: total,
            entries: entries,
            rates: portfolioRates,
            note: "Preview sample"
        )
    }

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
enum PreviewDefaults {
    static func primeOnboarded(homeCurrency: String = "USD") {
        UserDefaults.standard.set(true, forKey: AppSettingsKeys.onboardingCompleted)
        UserDefaults.standard.set(true, forKey: AppSettingsKeys.featureTourSeen)
        UserDefaults.standard.set(homeCurrency, forKey: AppSettingsKeys.homeCurrency)
    }
}
#endif

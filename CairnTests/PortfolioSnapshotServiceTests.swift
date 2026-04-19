import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class PortfolioSnapshotServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testDeleteRemovesUnderlyingMonthlySnapshots() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Checking", kind: .cash, member: member)
        let holdingA = Holding(currency: "USD", account: account)
        let holdingB = Holding(currency: "EUR", account: account)
        context.insert(member)
        context.insert(account)
        context.insert(holdingA)
        context.insert(holdingB)

        let targetMonth = Snapshot.normalize(.now)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: targetMonth) ?? targetMonth

        let snapshotTargetA = Snapshot(periodMonth: targetMonth, amount: 1_000, holding: holdingA)
        let snapshotTargetB = Snapshot(periodMonth: targetMonth, amount: 500, holding: holdingB)
        let snapshotPrevious = Snapshot(periodMonth: previousMonth, amount: 900, holding: holdingA)
        context.insert(snapshotTargetA)
        context.insert(snapshotTargetB)
        context.insert(snapshotPrevious)

        let entries: [PortfolioSnapshot.Entry] = [
            .init(
                holdingId: holdingA.id,
                memberName: member.name,
                accountName: account.name,
                holdingLabel: nil,
                currency: "USD",
                amount: 1_000,
                convertedAmount: 1_000
            ),
            .init(
                holdingId: holdingB.id,
                memberName: member.name,
                accountName: account.name,
                holdingLabel: nil,
                currency: "EUR",
                amount: 500,
                convertedAmount: 540
            )
        ]
        let portfolio = PortfolioSnapshot(
            periodMonth: targetMonth,
            homeCurrency: "USD",
            totalAmount: 1_540,
            entries: entries,
            rates: []
        )
        context.insert(portfolio)
        try context.save()

        try PortfolioSnapshotService.delete(portfolio, context: context)

        let remainingPortfolio = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        XCTAssertTrue(remainingPortfolio.isEmpty)

        let remainingSnapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(remainingSnapshots.count, 1)
        XCTAssertEqual(remainingSnapshots.first?.periodMonth, previousMonth)
    }

    func testDeleteLeavesOtherMonthsUntouched() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let thisMonth = Snapshot.normalize(.now)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth

        context.insert(Snapshot(periodMonth: thisMonth, amount: 100, holding: holding))
        context.insert(Snapshot(periodMonth: nextMonth, amount: 200, holding: holding))

        let portfolio = PortfolioSnapshot(
            periodMonth: thisMonth,
            homeCurrency: "USD",
            totalAmount: 100,
            entries: [
                .init(
                    holdingId: holding.id,
                    memberName: "",
                    accountName: account.name,
                    holdingLabel: nil,
                    currency: "USD",
                    amount: 100,
                    convertedAmount: 100
                )
            ],
            rates: []
        )
        context.insert(portfolio)
        try context.save()

        try PortfolioSnapshotService.delete(portfolio, context: context)

        let remaining = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.periodMonth, nextMonth)
    }

    /// Guards the multiply-vs-divide direction. The fetcher returns rates as
    /// `1 base == rate × quote` (here `1 USD = 0.93 EUR`), so converting a
    /// 1000 EUR holding back to USD must *divide* by the rate, not multiply:
    /// 1000 / 0.93 ≈ 1075.27 USD, not 930 USD.
    func testCaptureUsesCorrectConversionDirectionWithOnlineRates() async throws {
        let context = container.mainContext
        let account = Account(name: "Travel", kind: .cash)
        let holding = Holding(currency: "EUR", account: account)
        context.insert(account)
        context.insert(holding)

        let month = Snapshot.normalize(.now)
        context.insert(Snapshot(periodMonth: month, amount: 1_000, holding: holding))
        try context.save()

        let fetcher = StubFXFetcher(response: FXRateResponse(
            base: "USD",
            date: month,
            rates: ["EUR": 0.93]
        ))

        let portfolio = try await PortfolioSnapshotService.captureForMonth(
            month,
            homeCurrency: "USD",
            fetcher: fetcher,
            context: context
        )

        let entry = try XCTUnwrap(portfolio.entries.first(where: { $0.currency == "EUR" }))
        let converted = try XCTUnwrap(entry.convertedAmount)
        // 1000 EUR / 0.93 (EUR per USD) ≈ 1075.27 USD. Assert with a tiny
        // tolerance so the test doesn't depend on Decimal rounding specifics.
        let expected = Decimal(1_000) / Decimal(0.93)
        let delta = (converted - expected).magnitude
        XCTAssertLessThan(delta, Decimal(0.01))
        XCTAssertEqual(portfolio.totalAmount, converted)
    }

    /// When the online fetch fails and we fall back to the local FX cache,
    /// the conversion direction must match the online path so bakes stay
    /// consistent regardless of which branch produced the rate.
    func testCaptureUsesCorrectConversionDirectionWithCachedFallback() async throws {
        let context = container.mainContext
        // Seed the cache in the *inverse* direction (base=EUR, quote=USD)
        // to exercise the inverse fallback path.
        context.insert(FXRate(base: "EUR", quote: "USD", rate: Decimal(1) / Decimal(0.93)))

        let account = Account(name: "Travel", kind: .cash)
        let holding = Holding(currency: "EUR", account: account)
        context.insert(account)
        context.insert(holding)

        let month = Snapshot.normalize(.now)
        context.insert(Snapshot(periodMonth: month, amount: 1_000, holding: holding))
        try context.save()

        struct FailingFetcher: FXRateFetching {
            func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse {
                throw URLError(.notConnectedToInternet)
            }
        }

        let portfolio = try await PortfolioSnapshotService.captureForMonth(
            month,
            homeCurrency: "USD",
            fetcher: FailingFetcher(),
            context: context
        )

        let entry = try XCTUnwrap(portfolio.entries.first(where: { $0.currency == "EUR" }))
        let converted = try XCTUnwrap(entry.convertedAmount)
        let expected = Decimal(1_000) / Decimal(0.93)
        let delta = (converted - expected).magnitude
        XCTAssertLessThan(delta, Decimal(0.01))
    }
}

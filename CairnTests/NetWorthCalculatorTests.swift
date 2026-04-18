import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class NetWorthCalculatorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testTotalSumsInHomeCurrencyWhenNoConversionNeeded() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Primary", kind: .cash, member: member)
        let holding = Holding(currency: "USD", account: account)
        context.insert(member); context.insert(account); context.insert(holding)
        _ = SnapshotService.upsert(amount: 1_000, periodMonth: .now, for: holding, context: context)

        let totals = NetWorthCalculator.total(homeCurrency: "USD", context: context)
        XCTAssertEqual(totals.amount, 1_000)
        XCTAssertTrue(totals.missingCurrencies.isEmpty)
    }

    func testTotalConvertsUsingCachedRates() async throws {
        let context = container.mainContext
        let fetcher = StubFXFetcher(response: FXRateResponse(
            base: "USD",
            date: .now,
            rates: ["CNY": 7]
        ))
        try await FXService.refresh(base: "USD", quotes: ["CNY"], fetcher: fetcher, context: context)

        let member = Member(name: "Alice")
        let account = Account(name: "RMB", kind: .cash, member: member)
        let holding = Holding(currency: "CNY", account: account)
        context.insert(member); context.insert(account); context.insert(holding)
        _ = SnapshotService.upsert(amount: 7_000, periodMonth: .now, for: holding, context: context)

        let totals = NetWorthCalculator.total(homeCurrency: "USD", context: context)
        XCTAssertEqual(totals.amount, 1_000)
    }

    func testTotalReportsMissingCurrencies() throws {
        let context = container.mainContext
        let account = Account(name: "JPY", kind: .cash)
        let holding = Holding(currency: "JPY", account: account)
        context.insert(account); context.insert(holding)
        _ = SnapshotService.upsert(amount: 100_000, periodMonth: .now, for: holding, context: context)

        let totals = NetWorthCalculator.total(homeCurrency: "USD", context: context)
        XCTAssertEqual(totals.amount, 0)
        XCTAssertEqual(totals.missingCurrencies, ["JPY"])
    }

    func testArchivedHoldingsAreExcluded() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let active = Holding(currency: "USD", account: account)
        let archived = Holding(currency: "USD", account: account, isArchived: true)
        context.insert(account); context.insert(active); context.insert(archived)
        _ = SnapshotService.upsert(amount: 500, periodMonth: .now, for: active, context: context)
        _ = SnapshotService.upsert(amount: 9_000, periodMonth: .now, for: archived, context: context)

        let totals = NetWorthCalculator.total(homeCurrency: "USD", context: context)
        XCTAssertEqual(totals.amount, 500)
    }

    func testTotalUsesLatestSnapshotAtOrBeforeCutoff() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account); context.insert(holding)

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let jan = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now
        let feb = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let mar = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now

        _ = SnapshotService.upsert(amount: 100, periodMonth: jan, for: holding, context: context)
        _ = SnapshotService.upsert(amount: 200, periodMonth: feb, for: holding, context: context)
        _ = SnapshotService.upsert(amount: 300, periodMonth: mar, for: holding, context: context)

        let febTotals = NetWorthCalculator.total(homeCurrency: "USD", asOf: feb, context: context)
        XCTAssertEqual(febTotals.amount, 200)
    }

    func testTotalsByMember() throws {
        let context = container.mainContext
        let alice = Member(name: "Alice")
        let bob = Member(name: "Bob")
        let aliceAccount = Account(name: "A", kind: .cash, member: alice)
        let bobAccount = Account(name: "B", kind: .cash, member: bob)
        let aliceHolding = Holding(currency: "USD", account: aliceAccount)
        let bobHolding = Holding(currency: "USD", account: bobAccount)
        context.insert(alice)
        context.insert(bob)
        context.insert(aliceAccount)
        context.insert(bobAccount)
        context.insert(aliceHolding)
        context.insert(bobHolding)
        _ = SnapshotService.upsert(amount: 100, periodMonth: .now, for: aliceHolding, context: context)
        _ = SnapshotService.upsert(amount: 250, periodMonth: .now, for: bobHolding, context: context)

        let totals = NetWorthCalculator.totalsByMember(homeCurrency: "USD", context: context)
        let map = Dictionary(uniqueKeysWithValues: totals.map { ($0.memberName, $0.amount) })
        XCTAssertEqual(map["Alice"], 100)
        XCTAssertEqual(map["Bob"], 250)
    }

    func testTrendReturnsRequestedNumberOfMonths() throws {
        let context = container.mainContext
        let trend = NetWorthCalculator.trend(homeCurrency: "USD", months: 6, context: context)
        XCTAssertEqual(trend.count, 6)
        // Chronological order.
        for index in 1..<trend.count {
            XCTAssertLessThan(trend[index - 1].period, trend[index].period)
        }
    }
}

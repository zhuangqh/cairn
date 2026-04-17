import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class SnapshotServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testUpsertInsertsWhenAbsent() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)

        let snapshot = SnapshotService.upsert(
            amount: 1_000,
            periodMonth: .now,
            for: holding,
            context: context
        )
        XCTAssertEqual(snapshot.amount, 1_000)
        XCTAssertEqual((holding.snapshots ?? []).count, 1)
    }

    func testUpsertUpdatesExistingMonth() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)

        let month = Snapshot.normalize(.now)
        let first = SnapshotService.upsert(
            amount: 100,
            periodMonth: month,
            for: holding,
            context: context
        )
        let second = SnapshotService.upsert(
            amount: 250,
            periodMonth: month,
            for: holding,
            context: context
        )
        XCTAssertIdentical(first, second)
        XCTAssertEqual(second.amount, 250)
        XCTAssertEqual((holding.snapshots ?? []).count, 1)
    }

    func testUpsertNormalizesPeriodMonth() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)

        // Two different dates in the same month should collapse into one snapshot.
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let mid = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15)) ?? .now
        let end = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)) ?? .now

        SnapshotService.upsert(amount: 100, periodMonth: mid, for: holding, context: context)
        SnapshotService.upsert(amount: 200, periodMonth: end, for: holding, context: context)

        let snapshots = (holding.snapshots ?? [])
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.amount, 200)
    }
}

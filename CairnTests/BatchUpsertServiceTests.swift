import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class BatchUpsertServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testApplyCreatesSnapshotsForEnteredRows() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)
        try context.save()

        let rows = [BatchUpsertService.Row(holdingId: holding.id, amount: 1_000)]
        try BatchUpsertService.apply(rows, periodMonth: .now, context: context)

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.amount, 1_000)
    }

    func testApplySkipsNilRows() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let entered = Holding(currency: "USD", account: account)
        let blank = Holding(currency: "EUR", account: account)
        context.insert(account)
        context.insert(entered)
        context.insert(blank)
        try context.save()

        let rows = [
            BatchUpsertService.Row(holdingId: entered.id, amount: 500),
            BatchUpsertService.Row(holdingId: blank.id, amount: nil)
        ]
        try BatchUpsertService.apply(rows, periodMonth: .now, context: context)

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.holding?.currency, "USD")
    }

    func testApplyUpdatesExistingSnapshotForSameMonth() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)
        try context.save()

        try BatchUpsertService.apply(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 100)],
            periodMonth: .now,
            context: context
        )
        try BatchUpsertService.apply(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 250)],
            periodMonth: .now,
            context: context
        )

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.amount, 250)
    }

    func testReplaceMonthRemovesStaleSnapshotsBeforeWritingCurrentRows() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let laterInMonth = calendar.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let nextMonth = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!

        context.insert(Snapshot(periodMonth: monthStart, amount: 100, holding: holding))
        context.insert(Snapshot(periodMonth: laterInMonth, amount: 200, holding: holding))
        context.insert(Snapshot(periodMonth: nextMonth, amount: 300, holding: holding))
        try context.save()

        try BatchUpsertService.replaceMonth(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 500)],
            periodMonth: monthStart,
            context: context
        )

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
            .sorted { $0.periodMonth < $1.periodMonth }
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first?.periodMonth, Snapshot.normalizeDay(monthStart))
        XCTAssertEqual(snapshots.first?.amount, 500)
        XCTAssertEqual(snapshots.last?.periodMonth, Snapshot.normalizeDay(nextMonth))
        XCTAssertEqual(snapshots.last?.amount, 300)
    }

    func testReplaceMonthDeletesExistingRowsForBlankAmounts() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let holding = Holding(currency: "USD", account: account)
        context.insert(account)
        context.insert(holding)

        let month = Snapshot.normalize(.now)
        context.insert(Snapshot(periodMonth: month, amount: 100, holding: holding))
        try context.save()

        try BatchUpsertService.replaceMonth(
            [BatchUpsertService.Row(holdingId: holding.id, amount: nil)],
            periodMonth: month,
            context: context
        )

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertTrue(snapshots.isEmpty)
    }
}

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
}

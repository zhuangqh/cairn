import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class BackupServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testExportImportRoundTrip() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Primary", kind: .cash, member: member)
        let holding = Holding(currency: "USD", account: account)
        context.insert(member)
        context.insert(account)
        context.insert(holding)
        _ = SnapshotService.upsert(amount: 1_234, periodMonth: .now, for: holding, context: context)
        try context.save()

        let data = try BackupService.makeBackup(in: context)
        let payload = try BackupService.parse(data)
        XCTAssertEqual(payload.version, BackupService.currentVersion)
        XCTAssertEqual(payload.members.count, 1)
        XCTAssertEqual(payload.accounts.count, 1)
        XCTAssertEqual(payload.holdings.count, 1)
        XCTAssertEqual(payload.snapshots.count, 1)
        XCTAssertEqual(payload.members.first?.name, "Alice")
        XCTAssertEqual(payload.snapshots.first?.amount, 1_234)
    }

    func testRestoreReplacesExistingData() throws {
        // Populate store 1 and export.
        let sourceContext = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Primary", kind: .cash, member: member)
        let holding = Holding(currency: "USD", account: account)
        sourceContext.insert(member)
        sourceContext.insert(account)
        sourceContext.insert(holding)
        _ = SnapshotService.upsert(amount: 500, periodMonth: .now, for: holding, context: sourceContext)
        try sourceContext.save()
        let backup = try BackupService.makeBackup(in: sourceContext)

        // Fresh container with different data.
        let other = try PersistenceController.makeContainer(.inMemory)
        let targetContext = other.mainContext
        let bob = Member(name: "Bob")
        let bobAccount = Account(name: "Secondary", kind: .stock, member: bob)
        targetContext.insert(bob)
        targetContext.insert(bobAccount)
        try targetContext.save()

        _ = try BackupService.restoreReplacing(from: backup, context: targetContext)

        let members = try targetContext.fetch(FetchDescriptor<Member>())
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.name, "Alice")

        let holdings = try targetContext.fetch(FetchDescriptor<Holding>())
        XCTAssertEqual(holdings.count, 1)
        XCTAssertEqual(holdings.first?.account?.name, "Primary")

        let snapshots = try targetContext.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.amount, 500)
    }
}

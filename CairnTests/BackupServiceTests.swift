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

    func testExportImportRoundTripPreservesAssets() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        context.insert(member)
        let house = Asset(
            name: "Apartment",
            category: .realEstate,
            purchasePrice: 800_000,
            purchaseCurrency: "CNY",
            purchaseDate: Date(timeIntervalSince1970: 1_600_000_000),
            currentValue: 950_000,
            currentValueUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "Primary residence",
            member: member
        )
        let phone = Asset(
            name: "iPhone 15",
            category: .electronics,
            purchasePrice: 999,
            purchaseCurrency: "USD",
            purchaseDate: Date(timeIntervalSince1970: 1_650_000_000),
            saleDate: Date(timeIntervalSince1970: 1_700_500_000),
            salePrice: 420,
            member: member
        )
        context.insert(house)
        context.insert(phone)
        try context.save()

        let data = try BackupService.makeBackup(in: context)
        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: data, context: other.mainContext)

        let assets = try other.mainContext.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(assets.count, 2)
        let byName = Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0) })
        XCTAssertEqual(byName["Apartment"]?.category, .realEstate)
        XCTAssertEqual(byName["Apartment"]?.purchasePrice, 800_000)
        XCTAssertEqual(byName["Apartment"]?.currentValue, 950_000)
        XCTAssertEqual(byName["Apartment"]?.member?.name, "Alice")
        XCTAssertEqual(byName["iPhone 15"]?.isSold, true)
        XCTAssertEqual(byName["iPhone 15"]?.salePrice, 420)
    }

    func testRestoreOldBackupWithoutAssetsSucceeds() throws {
        // Simulate a pre-v1.1 backup: payload with no `assets` field.
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-01-01T00:00:00Z",
          "members": [],
          "accounts": [],
          "holdings": [],
          "snapshots": [],
          "fxRates": []
        }
        """.data(using: .utf8)!
        let other = try PersistenceController.makeContainer(.inMemory)
        let payload = try BackupService.restoreReplacing(from: json, context: other.mainContext)
        XCTAssertNil(payload.assets)
        let assets = try other.mainContext.fetch(FetchDescriptor<Asset>())
        XCTAssertTrue(assets.isEmpty)
    }

    func testParseRejectsBackupFromNewerVersion() throws {
        let future = BackupService.currentVersion + 1
        let json = """
        {
          "version": \(future),
          "exportedAt": "2026-01-01T00:00:00Z",
          "members": [],
          "accounts": [],
          "holdings": [],
          "snapshots": [],
          "fxRates": []
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try BackupService.parse(json)) { error in
            guard case DomainError.backupTooNew(let fileVersion, let supported) = error else {
                XCTFail("expected backupTooNew, got \(error)")
                return
            }
            XCTAssertEqual(fileVersion, future)
            XCTAssertEqual(supported, BackupService.currentVersion)
        }
    }

    func testParseRejectsCorruptPayload() throws {
        let garbage = Data("not json at all".utf8)
        XCTAssertThrowsError(try BackupService.parse(garbage)) { error in
            XCTAssertEqual(error as? DomainError, .backupUnreadable)
        }
    }

    func testRestorePreservesMemberAvatarData() throws {
        let context = container.mainContext
        let avatar = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
        let member = Member(name: "Alice", avatarData: avatar)
        context.insert(member)
        try context.save()

        let backup = try BackupService.makeBackup(in: context)
        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: backup, context: other.mainContext)

        let restored = try other.mainContext.fetch(FetchDescriptor<Member>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.avatarData, avatar)
    }

    func testRestorePreservesEntityIDs() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Primary", kind: .cash, member: member)
        let holding = Holding(currency: "USD", account: account)
        context.insert(member)
        context.insert(account)
        context.insert(holding)
        let memberId = member.id
        let accountId = account.id
        let holdingId = holding.id
        try context.save()

        let backup = try BackupService.makeBackup(in: context)
        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: backup, context: other.mainContext)

        let members = try other.mainContext.fetch(FetchDescriptor<Member>())
        let accounts = try other.mainContext.fetch(FetchDescriptor<Account>())
        let holdings = try other.mainContext.fetch(FetchDescriptor<Holding>())
        XCTAssertEqual(members.first?.id, memberId)
        XCTAssertEqual(accounts.first?.id, accountId)
        XCTAssertEqual(holdings.first?.id, holdingId)
    }

    func testRestoreIsIdempotentAcrossRepeatedImports() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Primary", kind: .cash, member: member)
        let holding = Holding(currency: "USD", account: account)
        context.insert(member)
        context.insert(account)
        context.insert(holding)
        try context.save()

        let backup = try BackupService.makeBackup(in: context)
        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: backup, context: other.mainContext)
        let firstMemberId = try other.mainContext.fetch(FetchDescriptor<Member>()).first?.id

        // Importing the same backup again must not duplicate or change ids.
        _ = try BackupService.restoreReplacing(from: backup, context: other.mainContext)
        let members = try other.mainContext.fetch(FetchDescriptor<Member>())
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.id, firstMemberId)
    }
}

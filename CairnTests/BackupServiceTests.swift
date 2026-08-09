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

    func testExportImportRoundTripPreservesPossessions() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        context.insert(member)
        let house = Possession(
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
        let phone = Possession(
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

        let possessions = try other.mainContext.fetch(FetchDescriptor<Possession>())
        XCTAssertEqual(possessions.count, 2)
        let byName = Dictionary(uniqueKeysWithValues: possessions.map { ($0.name, $0) })
        XCTAssertEqual(byName["Apartment"]?.category, .realEstate)
        XCTAssertEqual(byName["Apartment"]?.purchasePrice, 800_000)
        XCTAssertEqual(byName["Apartment"]?.currentValue, 950_000)
        XCTAssertEqual(byName["Apartment"]?.member?.name, "Alice")
        XCTAssertEqual(byName["iPhone 15"]?.isSold, true)
        XCTAssertEqual(byName["iPhone 15"]?.salePrice, 420)
    }

    func testExportImportRoundTripPreservesAchievements() throws {
        let context = container.mainContext
        let logicalMonth = Snapshot.normalize(Date(timeIntervalSince1970: 1_735_689_600))
        let unlockedAt = Date(timeIntervalSince1970: 1_738_368_000)
        let sourceSnapshotID = UUID()
        let event = AchievementEvent(
            eventKey: "ascent-AUD-2025-01",
            family: .monthlyAscent,
            stageKey: "ascent-4",
            logicalMonth: logicalMonth,
            unlockedAt: unlockedAt,
            currencyCode: "AUD",
            observedAmount: 245_000,
            source: .imported,
            sourceSnapshotIDs: [sourceSnapshotID],
            definitionVersion: 1
        )
        context.insert(event)
        try context.save()

        let data = try BackupService.makeBackup(in: context)
        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: data, context: other.mainContext)

        let restored = try XCTUnwrap(
            other.mainContext.fetch(FetchDescriptor<AchievementEvent>()).first
        )
        XCTAssertEqual(restored.id, event.id)
        XCTAssertEqual(restored.eventKey, "ascent-AUD-2025-01")
        XCTAssertEqual(restored.family, .monthlyAscent)
        XCTAssertEqual(restored.stageKey, "ascent-4")
        XCTAssertEqual(restored.logicalMonth, logicalMonth)
        XCTAssertEqual(restored.unlockedAt, unlockedAt)
        XCTAssertEqual(restored.currencyCode, "AUD")
        XCTAssertEqual(restored.observedAmount, 245_000)
        XCTAssertEqual(restored.source, .imported)
        XCTAssertEqual(restored.sourceSnapshotIDs, [sourceSnapshotID])
        XCTAssertEqual(restored.definitionVersion, 1)
    }

    func testRestoreOldBackupWithoutPossessionsSucceeds() throws {
        // Simulate a pre-v1.1 backup: payload with no `possessions` field.
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
        XCTAssertNil(payload.possessions)
        let possessions = try other.mainContext.fetch(FetchDescriptor<Possession>())
        XCTAssertTrue(possessions.isEmpty)
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

    func testRestoreCanonicalizesPortfolioEntryHoldingIDs() throws {
        let memberId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let accountId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let holdingId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let staleHoldingId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let portfolioId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let entryId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let json = """
        {
          "version": 3,
          "exportedAt": "2026-04-01T00:00:00Z",
          "members": [
            {
              "id": "\(memberId.uuidString)",
              "name": "Alice",
              "createdAt": "2026-01-01T00:00:00Z"
            }
          ],
          "accounts": [
            {
              "id": "\(accountId.uuidString)",
              "name": "Primary",
              "kindRawValue": "cash",
              "note": null,
              "isArchived": false,
              "createdAt": "2026-01-01T00:00:00Z",
              "memberId": "\(memberId.uuidString)"
            }
          ],
          "holdings": [
            {
              "id": "\(holdingId.uuidString)",
              "currency": "USD",
              "label": "Brokerage",
              "isArchived": false,
              "createdAt": "2026-01-01T00:00:00Z",
              "accountId": "\(accountId.uuidString)"
            }
          ],
          "snapshots": [],
          "fxRates": [],
          "portfolioSnapshots": [
            {
              "id": "\(portfolioId.uuidString)",
              "periodMonth": "2026-04-01T00:00:00Z",
              "homeCurrency": "USD",
              "totalAmount": 100,
              "note": null,
              "recordedAt": "2026-04-02T00:00:00Z",
              "entries": [
                {
                  "id": "\(entryId.uuidString)",
                  "holdingId": "\(staleHoldingId.uuidString)",
                  "memberName": "Alice",
                  "accountName": "Primary",
                  "accountKindRawValue": "cash",
                  "holdingLabel": "Brokerage",
                  "currency": "USD",
                  "amount": 100,
                  "convertedAmount": 100
                }
              ],
              "rates": []
            }
          ],
          "possessions": []
        }
        """.data(using: .utf8)!

        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: json, context: other.mainContext)

        let restored = try other.mainContext.fetch(FetchDescriptor<PortfolioSnapshot>())
        XCTAssertEqual(restored.first?.entries.first?.holdingId, holdingId)
    }

    func testRestoreClearsUnresolvablePortfolioEntryHoldingIDs() throws {
        let staleHoldingId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let portfolioId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let entryId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let json = """
        {
          "version": 3,
          "exportedAt": "2026-04-01T00:00:00Z",
          "members": [],
          "accounts": [],
          "holdings": [],
          "snapshots": [],
          "fxRates": [],
          "portfolioSnapshots": [
            {
              "id": "\(portfolioId.uuidString)",
              "periodMonth": "2026-04-01T00:00:00Z",
              "homeCurrency": "USD",
              "totalAmount": 100,
              "note": null,
              "recordedAt": "2026-04-02T00:00:00Z",
              "entries": [
                {
                  "id": "\(entryId.uuidString)",
                  "holdingId": "\(staleHoldingId.uuidString)",
                  "memberName": "Alice",
                  "accountName": "Primary",
                  "currency": "USD",
                  "amount": 100,
                  "convertedAmount": 100
                }
              ],
              "rates": []
            }
          ],
          "possessions": []
        }
        """.data(using: .utf8)!

        let other = try PersistenceController.makeContainer(.inMemory)
        _ = try BackupService.restoreReplacing(from: json, context: other.mainContext)

        let restored = try other.mainContext.fetch(FetchDescriptor<PortfolioSnapshot>())
        XCTAssertNil(restored.first?.entries.first?.holdingId)
    }

    func testSnapshotCSVExportsBatchRowsInNativeCurrencies() throws {
        let context = container.mainContext
        let alice = Member(name: "Alice")
        let cash = Account(name: "Cash", kind: .cash, member: alice)
        let cnyHolding = Holding(currency: "CNY", label: "Everyday", account: cash)
        let bob = Member(name: "Bob")
        let broker = Account(name: "Broker, AU", kind: .stock, member: bob)
        let usdHolding = Holding(currency: "USD", account: broker)
        context.insert(alice)
        context.insert(cash)
        context.insert(cnyHolding)
        context.insert(bob)
        context.insert(broker)
        context.insert(usdHolding)
        context.insert(Snapshot(periodMonth: date("2026-02-15T00:00:00Z"), amount: 500, holding: cnyHolding))
        context.insert(Snapshot(periodMonth: date("2026-02-15T00:00:00Z"), amount: 12.34, holding: usdHolding))
        context.insert(Snapshot(periodMonth: date("2026-03-20T00:00:00Z"), amount: 750, holding: cnyHolding))

        let first = PortfolioSnapshot(
            periodMonth: date("2026-02-01T00:00:00Z"),
            homeCurrency: "AUD",
            totalAmount: 999,
            entries: [
                PortfolioSnapshot.Entry(
                    holdingId: usdHolding.id,
                    memberName: "Bob",
                    accountName: "Broker, AU",
                    holdingLabel: nil,
                    currency: "USD",
                    amount: 12.34,
                    convertedAmount: 99
                ),
                PortfolioSnapshot.Entry(
                    holdingId: cnyHolding.id,
                    memberName: "Alice",
                    accountName: "Cash",
                    holdingLabel: "Everyday",
                    currency: "CNY",
                    amount: 500,
                    convertedAmount: 100
                )
            ],
            rates: [
                PortfolioSnapshot.Rate(base: "AUD", quote: "CNY", rate: 4.75),
                PortfolioSnapshot.Rate(base: "AUD", quote: "USD", rate: 0.66)
            ],
            note: "first, batch",
            recordedAt: date("2026-02-02T03:04:05Z")
        )
        let second = PortfolioSnapshot(
            periodMonth: date("2026-03-01T00:00:00Z"),
            homeCurrency: "AUD",
            totalAmount: 1_500,
            entries: [
                PortfolioSnapshot.Entry(
                    holdingId: cnyHolding.id,
                    memberName: "Alice",
                    accountName: "Cash",
                    holdingLabel: "Everyday",
                    currency: "CNY",
                    amount: 750,
                    convertedAmount: 150
                )
            ],
            rates: [
                PortfolioSnapshot.Rate(base: "AUD", quote: "CNY", rate: 4.90)
            ],
            recordedAt: date("2026-03-02T03:04:05Z")
        )
        context.insert(second)
        context.insert(first)
        try context.save()

        let csv = String(decoding: try BackupService.makeSnapshotCSV(in: context), as: UTF8.self)

        XCTAssertEqual(
            csv,
            """
            date,period,recordedAt,homeCurrency,totalAmount,note,rateDate,rate CNY->AUD,rate USD->AUD,Alice / Cash / Everyday (CNY),"Bob / Broker, AU (USD)"
            2026-02-15,2026-02-01,2026-02-02T03:04:05Z,AUD,999,"first, batch",2026-02-15,0.21,1.52,500,12.34
            2026-03-20,2026-03-01,2026-03-02T03:04:05Z,AUD,1500,,2026-03-20,0.20,,750,

            """
        )
        XCTAssertFalse(csv.contains(",100,"))
        XCTAssertFalse(csv.contains(",150\n"))
    }

    func testSnapshotCSVKeepsDirectForeignToHomeRates() throws {
        let context = container.mainContext
        let portfolio = PortfolioSnapshot(
            periodMonth: date("2026-02-01T00:00:00Z"),
            homeCurrency: "AUD",
            totalAmount: 100,
            entries: [],
            rates: [
                PortfolioSnapshot.Rate(base: "USD", quote: "AUD", rate: 1.52)
            ],
            recordedAt: date("2026-02-02T03:04:05Z")
        )
        context.insert(portfolio)
        try context.save()

        let csv = String(decoding: try BackupService.makeSnapshotCSV(in: context), as: UTF8.self)

        XCTAssertEqual(
            csv,
            """
            date,period,recordedAt,homeCurrency,totalAmount,note,rateDate,rate USD->AUD
            2026-02-01,2026-02-01,2026-02-02T03:04:05Z,AUD,100,,2026-02-01,1.52

            """
        )
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

    private func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }
}

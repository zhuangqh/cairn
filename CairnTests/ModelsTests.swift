import XCTest
import SwiftData
@testable import Cairn

final class ModelsTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    @MainActor
    func testMemberCascadeDeletesAccountsAndHoldings() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Primary", kind: .cash, member: member)
        let cny = Holding(currency: "CNY", account: account)
        let usd = Holding(currency: "USD", account: account)
        context.insert(member)
        context.insert(account)
        context.insert(cny)
        context.insert(usd)
        try context.save()

        context.delete(member)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let holdings = try context.fetch(FetchDescriptor<Holding>())
        XCTAssertEqual(accounts.count, 0)
        XCTAssertEqual(holdings.count, 0)
    }

    func testSnapshotPeriodNormalization() {
        let mid = Date(timeIntervalSince1970: 1_713_456_789) // 2024-04-18T14:53:09Z
        let normalized = Snapshot.normalize(mid)

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: normalized)

        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)
    }

    func testAccountKindLocalizationKeysAreStable() {
        XCTAssertEqual(AccountKind.cash.localizationKey, "account.kind.cash")
        XCTAssertEqual(AccountKind.stock.localizationKey, "account.kind.stock")
        XCTAssertEqual(AccountKind.realEstate.localizationKey, "account.kind.realEstate")
        XCTAssertEqual(AccountKind.device.localizationKey, "account.kind.device")
    }

    func testAccountKindRawValuesAreFrozen() {
        // Raw values are persisted — changing them is a breaking migration.
        XCTAssertEqual(AccountKind.cash.rawValue, "cash")
        XCTAssertEqual(AccountKind.stock.rawValue, "stock")
        XCTAssertEqual(AccountKind.realEstate.rawValue, "realEstate")
        XCTAssertEqual(AccountKind.device.rawValue, "device")
    }

    @MainActor
    func testCreateAccountAndHoldingGraph() throws {
        let context = container.mainContext
        let member = Member(name: "Bob")
        context.insert(member)

        let account = Account(name: "Futu", kind: .stock, member: member)
        context.insert(account)

        let usd = Holding(currency: "USD", account: account)
        context.insert(usd)

        let snapshot = Snapshot(
            periodMonth: Date(timeIntervalSince1970: 1_713_456_789),
            amount: Decimal(string: "12345.67") ?? 0,
            holding: usd
        )
        context.insert(snapshot)

        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.holding?.currency, "USD")
        XCTAssertEqual(fetched.first?.holding?.account?.kind, .stock)
        XCTAssertEqual(fetched.first?.holding?.account?.member?.name, "Bob")
    }
}

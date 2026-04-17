import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class HoldingServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testCreateInsertsHolding() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Primary", kind: .cash, member: member)
        context.insert(member)
        context.insert(account)

        let holding = try HoldingService.create(currency: "CNY", in: account, context: context)
        XCTAssertEqual(holding.currency, "CNY")
        XCTAssertEqual((account.holdings ?? []).count, 1)
    }

    func testDuplicateCurrencyIsRejected() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        context.insert(account)

        _ = try HoldingService.create(currency: "USD", in: account, context: context)
        XCTAssertThrowsError(
            try HoldingService.create(currency: "USD", in: account, context: context)
        ) { error in
            XCTAssertEqual(error as? DomainError, .duplicateCurrencyInAccount(currency: "USD"))
        }
    }

    func testArchivedHoldingDoesNotBlockSameCurrency() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        context.insert(account)

        let first = try HoldingService.create(currency: "USD", in: account, context: context)
        first.isArchived = true

        let replacement = try HoldingService.create(currency: "USD", in: account, context: context)
        XCTAssertEqual(replacement.currency, "USD")
        XCTAssertFalse(replacement.isArchived)
    }
}

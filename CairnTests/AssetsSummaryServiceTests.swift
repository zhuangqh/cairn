import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class AssetsSummaryServiceTests: InMemoryStoreTestCase {
    func testLiveSummaryWithoutPortfolioSnapshotUsesHoldingsAndPriorMonth() throws {
        let context = container.mainContext
        let member = Member(name: "Alice")
        let account = Account(name: "Checking", kind: .cash, member: member)
        let holding = Holding(currency: "USD", account: account)
        context.insert(member); context.insert(account); context.insert(holding)
        let thisMonth = Snapshot.normalize(.now)
        let lastMonth = try XCTUnwrap(Snapshot.adding(months: -1, to: thisMonth))
        _ = SnapshotService.upsert(amount: 800, periodMonth: lastMonth, for: holding, context: context)
        _ = SnapshotService.upsert(amount: 1_000, periodMonth: .now, for: holding, context: context)

        let summary = AssetsSummaryService.liveSummary(homeCurrency: "USD", context: context)

        XCTAssertNil(summary.sourceSnapshot)
        XCTAssertEqual(summary.totals.amount, 1_000)
        XCTAssertEqual(summary.monthDeltaAmount, 200)
        XCTAssertEqual(try XCTUnwrap(summary.monthDeltaPercent), 0.25, accuracy: 1e-9)
        XCTAssertEqual(summary.memberTotals.map(\.memberId), [member.id])
        XCTAssertEqual(try XCTUnwrap(summary.memberDeltaPercent[member.id]), 0.25, accuracy: 1e-9)
        XCTAssertEqual(summary.currencyTotals.map(\.currency), ["USD"])
        XCTAssertEqual(try XCTUnwrap(summary.currencyDeltaPercent["USD"]), 0.25, accuracy: 1e-9)
    }

    func testSnapshotSummaryUsesCapturedValuesAndResolvesMembers() throws {
        let context = container.mainContext
        let alice = Member(name: "Alice")
        let bob = Member(name: "Bob")
        let carol = Member(name: "Carol")
        let account = Account(name: "Checking", kind: .cash, member: alice)
        let holding = Holding(currency: "USD", account: account)
        [alice, bob, carol].forEach(context.insert)
        context.insert(account); context.insert(holding)
        // Live balance differs from the captured one; the summary must not use it.
        _ = SnapshotService.upsert(amount: 9_999, periodMonth: .now, for: holding, context: context)

        let thisMonth = Snapshot.normalize(.now)
        let lastMonth = try XCTUnwrap(Snapshot.adding(months: -1, to: thisMonth))
        let previous = makePortfolio(month: lastMonth, total: 1_500, entries: [
            entry(holdingId: holding.id, member: "Renamed", currency: "USD", amount: 1_000, converted: 1_000),
            entry(holdingId: nil, member: "Bob", currency: "EUR", amount: 400, converted: 500)
        ])
        let latest = makePortfolio(month: thisMonth, total: 1_800, entries: [
            // Resolved through the live holding even though the captured name differs.
            entry(holdingId: holding.id, member: "Renamed", currency: "USD", amount: 1_200, converted: 1_200),
            // Deleted holding: resolved by captured member name.
            entry(holdingId: nil, member: "Bob", currency: "EUR", amount: 500, converted: 600),
            // No rate at capture time: excluded from member totals.
            entry(holdingId: nil, member: "Carol", currency: "JPY", amount: 10_000, converted: nil)
        ])
        context.insert(previous); context.insert(latest)

        let summary = AssetsSummaryService.summary(
            from: latest,
            previous: previous,
            members: [bob, carol, alice],
            holdings: [holding]
        )

        XCTAssertTrue(summary.sourceSnapshot === latest)
        XCTAssertEqual(summary.totals.amount, 1_800)
        XCTAssertTrue(summary.totals.missingCurrencies.isEmpty)
        XCTAssertEqual(summary.monthDeltaAmount, 300)
        XCTAssertEqual(try XCTUnwrap(summary.monthDeltaPercent), 0.2, accuracy: 1e-9)
        // Member rows follow the given member order; Carol has no converted amount.
        XCTAssertEqual(summary.memberTotals.map(\.memberId), [bob.id, alice.id])
        XCTAssertEqual(summary.memberTotals.map(\.amount), [600, 1_200])
        XCTAssertEqual(try XCTUnwrap(summary.memberDeltaPercent[alice.id]), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.memberDeltaPercent[bob.id]), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.currencyDeltaPercent["USD"]), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.currencyDeltaPercent["EUR"]), 0.2, accuracy: 1e-9)
        XCTAssertNil(summary.currencyDeltaPercent["JPY"])
    }

    func testSnapshotSummaryWithoutPreviousHasNoDeltas() {
        let context = container.mainContext
        let alice = Member(name: "Alice")
        context.insert(alice)
        let latest = makePortfolio(month: Snapshot.normalize(.now), total: 700, entries: [
            entry(holdingId: nil, member: "Alice", currency: "USD", amount: 700, converted: 700)
        ])
        context.insert(latest)

        let summary = AssetsSummaryService.summary(
            from: latest,
            previous: nil,
            members: [alice],
            holdings: []
        )

        XCTAssertEqual(summary.totals.amount, 700)
        XCTAssertNil(summary.monthDeltaAmount)
        XCTAssertNil(summary.monthDeltaPercent)
        XCTAssertTrue(summary.memberDeltaPercent.isEmpty)
        XCTAssertTrue(summary.currencyDeltaPercent.isEmpty)
        XCTAssertEqual(summary.memberTotals.map(\.amount), [700])
    }

    // MARK: - Fixtures

    private func makePortfolio(
        month: Date,
        total: Decimal,
        entries: [PortfolioSnapshot.Entry]
    ) -> PortfolioSnapshot {
        PortfolioSnapshot(
            periodMonth: month,
            homeCurrency: "USD",
            totalAmount: total,
            entries: entries,
            rates: []
        )
    }

    private func entry(
        holdingId: UUID?,
        member: String,
        currency: String,
        amount: Decimal,
        converted: Decimal?
    ) -> PortfolioSnapshot.Entry {
        PortfolioSnapshot.Entry(
            holdingId: holdingId,
            memberName: member,
            accountName: "Account",
            holdingLabel: nil,
            currency: currency,
            amount: amount,
            convertedAmount: converted
        )
    }
}

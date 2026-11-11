import XCTest
@testable import Cairn

/// Market / FX / manual-update decomposition between two captured snapshots.
final class PortfolioChangeBreakdownTests: XCTestCase {
    private let home = "USD"

    private func entry(
        _ holdingId: UUID?,
        _ currency: String,
        _ amount: Decimal,
        converted: Decimal?
    ) -> PortfolioSnapshot.Entry {
        PortfolioSnapshot.Entry(
            holdingId: holdingId,
            memberName: "M",
            accountName: "A",
            holdingLabel: nil,
            currency: currency,
            amount: amount,
            convertedAmount: converted
        )
    }

    func testNoPriorSnapshotHasNoBreakdown() {
        let current = [entry(UUID(), "USD", 100, converted: 100)]
        XCTAssertNil(PortfolioChangeBreakdown.compute(current: current, prior: nil, homeCurrency: home))
    }

    func testEmptyPriorCountsEverythingAsAdded() throws {
        let current = [entry(UUID(), "USD", 100, converted: 100)]
        let result = try XCTUnwrap(PortfolioChangeBreakdown.compute(current: current, prior: [], homeCurrency: home))
        XCTAssertEqual(result.manualAdded, 100)
        XCTAssertEqual(result.manualRemoved, 0)
        XCTAssertEqual(result.market, 0)
        XCTAssertEqual(result.fx, 0)
        XCTAssertTrue(result.hasContent)
    }

    func testMatchedHoldingsSplitMarketAndFX() throws {
        let cash = UUID(), cny = UUID(), eur = UUID()
        let prior = [
            entry(cash, "USD", 100, converted: 100),
            entry(cny, "CNY", 800, converted: 100),   // rate 8 CNY / USD
            entry(eur, "EUR", 100, converted: 125)    // rate 0.8 EUR / USD
        ]
        let current = [
            entry(cash, "USD", 150, converted: 150),
            entry(cny, "CNY", 1_000, converted: 125), // rate unchanged
            entry(eur, "EUR", 100, converted: 100)    // rate now 1
        ]
        let result = try XCTUnwrap(PortfolioChangeBreakdown.compute(current: current, prior: prior, homeCurrency: home))

        XCTAssertEqual(result.market, 75)   // 50 USD + 200 CNY / 8
        XCTAssertEqual(result.fx, -25)      // 100 EUR × (1/1 − 1/0.8)
        XCTAssertEqual(result.manualNet, 0)
        XCTAssertEqual(result.fxRateChanges.map(\.currency), ["EUR"])
        XCTAssertEqual(result.fxRateChanges.first?.oldRate, Decimal(string: "1.25"))
        XCTAssertEqual(result.fxRateChanges.first?.newRate, 1)
        // The parts reconcile with the total change in home currency.
        XCTAssertEqual(result.market + result.fx + result.manualNet, 375 - 325)
    }

    func testAddedRemovedAndCurrencyChangedHoldingsAreManual() throws {
        let removed = UUID(), switched = UUID(), added = UUID()
        let prior = [
            entry(removed, "USD", 50, converted: 50),
            entry(switched, "CNY", 700, converted: 100),
            entry(nil, "USD", 5, converted: 5)          // no id: cannot be matched or removed
        ]
        let current = [
            entry(switched, "USD", 120, converted: 120), // currency changed: remove + add
            entry(added, "USD", 30, converted: 30),
            entry(nil, "USD", 10, converted: 10)         // no id: added
        ]
        let result = try XCTUnwrap(PortfolioChangeBreakdown.compute(current: current, prior: prior, homeCurrency: home))

        XCTAssertEqual(result.manualAdded, 160)
        XCTAssertEqual(result.manualRemoved, -150)
        XCTAssertEqual(result.manualNet, 10)
        XCTAssertEqual(result.market, 0)
        XCTAssertEqual(result.fx, 0)
        XCTAssertTrue(result.fxRateChanges.isEmpty)
    }

    func testMissingConversionsAndZeroPriorFallBack() throws {
        let zeroPrior = UUID(), unconverted = UUID(), addedUnconverted = UUID()
        let prior = [
            entry(zeroPrior, "CNY", 0, converted: 0),
            entry(unconverted, "EUR", 100, converted: 110)
        ]
        let current = [
            entry(zeroPrior, "CNY", 800, converted: 100), // zero baseline: all market
            entry(unconverted, "EUR", 120, converted: nil), // no rate now: skipped
            entry(addedUnconverted, "JPY", 1_000, converted: nil)
        ]
        let result = try XCTUnwrap(PortfolioChangeBreakdown.compute(current: current, prior: prior, homeCurrency: home))

        XCTAssertEqual(result.market, 100)
        XCTAssertEqual(result.fx, 0)
        XCTAssertEqual(result.manualAdded, 0)
        XCTAssertEqual(result.manualRemoved, 0)
        XCTAssertTrue(result.fxRateChanges.isEmpty)
        XCTAssertFalse(result.hasContent)
    }

    func testEntriesByHoldingSkipsMissingIdsAndKeepsLastDuplicate() {
        let id = UUID()
        let map = PortfolioChangeBreakdown.entriesByHolding([
            entry(id, "USD", 1, converted: 1),
            entry(nil, "USD", 2, converted: 2),
            entry(id, "USD", 3, converted: 3)
        ])
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map[id]?.amount, 3)
    }
}

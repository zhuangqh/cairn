import XCTest
import SwiftData
@testable import Cairn

struct StubFXFetcher: FXRateFetching {
    let response: FXRateResponse

    func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse {
        response
    }
}

@MainActor
final class FXServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testRefreshInsertsRates() async throws {
        let context = container.mainContext
        let fetcher = StubFXFetcher(response: FXRateResponse(
            base: "USD",
            date: .now,
            rates: ["EUR": 0.9, "CNY": 7.1]
        ))
        try await FXService.refresh(base: "USD", quotes: ["EUR", "CNY"], fetcher: fetcher, context: context)

        let rates = try context.fetch(FetchDescriptor<FXRate>())
        XCTAssertEqual(rates.count, 2)
        XCTAssertEqual(FXService.latestRate(base: "USD", quote: "EUR", in: context)?.rate, 0.9)
    }

    func testRefreshUpdatesExistingRow() async throws {
        let context = container.mainContext
        let first = StubFXFetcher(response: FXRateResponse(base: "USD", date: .now, rates: ["EUR": 0.9]))
        try await FXService.refresh(base: "USD", quotes: ["EUR"], fetcher: first, context: context)

        let second = StubFXFetcher(response: FXRateResponse(base: "USD", date: .now, rates: ["EUR": 0.95]))
        try await FXService.refresh(base: "USD", quotes: ["EUR"], fetcher: second, context: context)

        let rates = try context.fetch(FetchDescriptor<FXRate>())
        XCTAssertEqual(rates.count, 1)
        XCTAssertEqual(rates.first?.rate, 0.95)
    }

    func testConvertUsesDirectRate() async throws {
        let context = container.mainContext
        let fetcher = StubFXFetcher(response: FXRateResponse(base: "USD", date: .now, rates: ["CNY": 7]))
        try await FXService.refresh(base: "USD", quotes: ["CNY"], fetcher: fetcher, context: context)

        let converted = FXService.convert(amount: 10, from: "USD", to: "CNY", in: context)
        XCTAssertEqual(converted, 70)
    }

    func testConvertFallsBackToInverse() async throws {
        let context = container.mainContext
        // Only USD->CNY cached; request CNY->USD.
        let fetcher = StubFXFetcher(response: FXRateResponse(base: "USD", date: .now, rates: ["CNY": 8]))
        try await FXService.refresh(base: "USD", quotes: ["CNY"], fetcher: fetcher, context: context)

        let converted = FXService.convert(amount: 80, from: "CNY", to: "USD", in: context)
        XCTAssertEqual(converted, 10)
    }

    func testConvertIdentityReturnsAmount() {
        let context = container.mainContext
        XCTAssertEqual(FXService.convert(amount: 42, from: "USD", to: "USD", in: context), 42)
    }

    func testConvertReturnsNilWhenRateMissing() {
        let context = container.mainContext
        XCTAssertNil(FXService.convert(amount: 10, from: "USD", to: "JPY", in: context))
    }
}

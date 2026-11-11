import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class FXServiceTests: InMemoryStoreTestCase {
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

    /// The batch-entry sheet swapped per-row `convert(in:)` fetches for one
    /// `RateCache`; both must agree on direct, inverse, zero-inverse,
    /// identity, and missing pairs.
    func testRateCacheConvertMatchesContextConvert() throws {
        let context = container.mainContext
        context.insert(FXRate(base: "USD", quote: "CNY", rate: Decimal(71_234) / 10_000, date: .now))
        context.insert(FXRate(base: "EUR", quote: "USD", rate: Decimal(10_876) / 10_000, date: .now))
        context.insert(FXRate(base: "GBP", quote: "USD", rate: 0, date: .now))
        try context.save()
        let cache = FXService.RateCache.load(in: context)

        let pairs = [
            ("USD", "CNY"), ("CNY", "USD"), ("EUR", "USD"), ("USD", "EUR"),
            ("USD", "GBP"), ("GBP", "USD"), ("USD", "USD"), ("USD", "JPY"), ("JPY", "USD")
        ]
        let amount = Decimal(1_234_567) / 100
        for (from, to) in pairs {
            XCTAssertEqual(
                cache.convert(amount: amount, from: from, to: to),
                FXService.convert(amount: amount, from: from, to: to, in: context),
                "\(from)->\(to)"
            )
        }
    }

    /// Rates must match the published literals exactly, not the nearest
    /// binary double (`Decimal(0.1)` is 0.1000000000000000512).
    func testFrankfurterDecodingKeepsPublishedRatesExact() throws {
        let json = """
        {"amount":1.0,"base":"USD","date":"2026-02-13",
         "rates":{"EUR":0.1,"JPY":157.23,"IDR":16234.5,"BTC":0.00001234,"KRW":1450}}
        """
        let response = try FrankfurterFetcher.decodeResponse(Data(json.utf8))

        XCTAssertEqual(response.base, "USD")
        XCTAssertEqual(response.date, try date("2026-02-13T00:00:00Z"))
        let expected = ["EUR": "0.1", "JPY": "157.23", "IDR": "16234.5", "BTC": "0.00001234", "KRW": "1450"]
        for (quote, literal) in expected {
            XCTAssertEqual(response.rates[quote], Decimal(string: literal), quote)
        }
    }
}

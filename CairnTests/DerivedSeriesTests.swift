import XCTest
import SwiftData
@testable import Cairn

/// Equivalence checks for single-pass rewrites of per-render derivations.
@MainActor
final class DerivedSeriesTests: InMemoryStoreTestCase {
    // MARK: - Trend possession overlay

    func testCumulativeSeriesMatchesPerPeriodScan() {
        let calendar = Calendar(identifier: .gregorian)
        func month(_ year: Int, _ month: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
        }
        let periods = (1...12).map { month(2025, $0) }
        // Unsorted entries, a duplicate month, one before and one after the window.
        let entries: [(month: Date, amount: Decimal)] = [
            (month(2025, 6), 300),
            (month(2024, 11), 1_000),
            (month(2025, 3), Decimal(4_555) / 100),
            (month(2025, 6), 20),
            (month(2026, 2), 9_999),
            (month(2025, 1), 5)
        ]

        let expected = periods.reduce(into: [Date: Decimal]()) { result, period in
            var sum: Decimal = 0
            for entry in entries where entry.month <= period { sum += entry.amount }
            result[period] = sum
        }
        XCTAssertEqual(TrendChartView.cumulativeSeries(periods: periods, entries: entries), expected)
        XCTAssertEqual(TrendChartView.cumulativeSeries(periods: periods.reversed(), entries: entries), expected)
        XCTAssertEqual(TrendChartView.cumulativeSeries(periods: periods, entries: []), periods.reduce(into: [:]) { $0[$1] = 0 })
    }

    // MARK: - Assets snapshot predecessors

    func testPreviousSnapshotsMatchFirstEarlierSameCurrencyMatch() throws {
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        func month(_ year: Int, _ month: Int) -> Date {
            calendar.date(from: DateComponents(timeZone: .gmt, year: year, month: month, day: 15)) ?? .distantPast
        }
        // (month of 2024, home currency), including equal months.
        let specs: [(month: Int, currency: String)] = [
            (1, "USD"), (2, "USD"), (2, "USD"), (3, "CNY"),
            (4, "USD"), (4, "CNY"), (6, "USD"), (6, "USD")
        ]
        for (monthValue, currency) in specs {
            context.insert(PortfolioSnapshot(
                periodMonth: month(2024, monthValue),
                homeCurrency: currency,
                totalAmount: 1,
                entries: [],
                rates: []
            ))
        }
        try context.save()
        let descending = try context.fetch(FetchDescriptor<PortfolioSnapshot>(
            sortBy: [SortDescriptor(\.periodMonth, order: .reverse)]
        ))

        let map = AssetsView.previousSnapshots(in: descending)
        for snapshot in descending {
            let expected = descending.first {
                $0.homeCurrency == snapshot.homeCurrency && $0.periodMonth < snapshot.periodMonth
            }
            XCTAssertTrue(
                map[ObjectIdentifier(snapshot)] === expected,
                "\(snapshot.homeCurrency) \(snapshot.periodMonth)"
            )
        }
    }
}

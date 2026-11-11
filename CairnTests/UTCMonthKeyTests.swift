import XCTest
@testable import Cairn

/// Snapshot day/month keys are UTC midnight; labels and year buckets must
/// not shift them when the device is west of UTC.
@MainActor
final class UTCMonthKeyTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    override func setUp() {
        super.setUp()
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    }

    override func tearDown() {
        NSTimeZone.default = NSTimeZone.system
        super.tearDown()
    }

    private func key(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        Snapshot.utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func testYearFilterBucketsUTCKeysByUTCYear() {
        let keys = [key(2024, 1), key(2024, 12, 31), key(2025, 1)]
        XCTAssertEqual(LedgerYearFilterMenu.years(of: keys), [2025, 2024])
        XCTAssertEqual(LedgerYearFilterMenu.filter(keys, year: 2024, date: { $0 }), [key(2024, 1), key(2024, 12, 31)])
        XCTAssertEqual(LedgerYearFilterMenu.filter(keys, year: 2025, date: { $0 }), [key(2025, 1)])
    }

    func testUTCFormatKeepsKeyMonthAndDay() {
        let enUS = Locale(identifier: "en_US")
        XCTAssertEqual(key(2025, 1).formatted(.dateTime.year().month(.wide).locale(enUS).inUTC), "January 2025")
        XCTAssertEqual(key(2025, 3, 1).formatted(.dateTime.year().month().day().locale(enUS).inUTC), "Mar 1, 2025")
    }

    func testPossessionMonthAnchorUsesLocalMonthAsUTCKey() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = losAngeles
        // Picked as Jan 1 local; already Jan 1 08:00 in UTC, and Dec 31 local
        // is Jan 1 UTC late in the evening.
        let newYearsDay = local.date(from: DateComponents(year: 2025, month: 1, day: 1)) ?? .distantPast
        let newYearsEve = local.date(from: DateComponents(year: 2024, month: 12, day: 31, hour: 20)) ?? .distantPast
        XCTAssertEqual(TrendChartView.monthAnchor(of: newYearsDay, calendar: local), key(2025, 1))
        XCTAssertEqual(TrendChartView.monthAnchor(of: newYearsEve, calendar: local), key(2024, 12))

        // A January purchase counts toward the January (UTC) trend period.
        let series = TrendChartView.cumulativeSeries(
            periods: [key(2024, 12), key(2025, 1)],
            entries: [(TrendChartView.monthAnchor(of: newYearsDay, calendar: local) ?? .distantFuture, 10)]
        )
        XCTAssertEqual(series, [key(2024, 12): 0, key(2025, 1): 10])
    }
}

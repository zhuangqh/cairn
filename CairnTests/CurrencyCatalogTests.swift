import XCTest
@testable import Cairn

final class CurrencyCatalogTests: XCTestCase {
    func testPinnedCodesAreSubsetOfAll() {
        let allSet = Set(CurrencyCatalog.all)
        for code in CurrencyCatalog.pinned {
            XCTAssertTrue(allSet.contains(code), "Pinned code \(code) is missing from all ISO codes")
        }
    }

    func testRestExcludesPinned() {
        let pinnedSet = Set(CurrencyCatalog.pinned)
        for code in CurrencyCatalog.rest {
            XCTAssertFalse(pinnedSet.contains(code))
        }
    }

    func testPinnedContainsCommonTargets() {
        XCTAssertTrue(CurrencyCatalog.pinned.contains("CNY"))
        XCTAssertTrue(CurrencyCatalog.pinned.contains("USD"))
        XCTAssertTrue(CurrencyCatalog.pinned.contains("HKD"))
        XCTAssertTrue(CurrencyCatalog.pinned.contains("AUD"))
    }

    @MainActor
    func testCompactCurrencyFormatterAbbreviatesLargeValues() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(
            CompactCurrencyFormatter.string(amount: Decimal(12_345), code: "USD", locale: locale),
            "$12.3K"
        )
        XCTAssertEqual(
            CompactCurrencyFormatter.string(amount: Decimal(1_234_567), code: "USD", locale: locale),
            "$1.23M"
        )
    }
}

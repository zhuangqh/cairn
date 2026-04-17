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
}

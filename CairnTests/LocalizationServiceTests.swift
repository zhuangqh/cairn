import XCTest
@testable import Cairn

final class LocalizationServiceTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "cairn.languageOverride")
    }

    func testDefaultsToFollowSystem() {
        let service = LocalizationService()
        XCTAssertEqual(service.override, .followSystem)
        XCTAssertNil(service.effectiveLocale)
    }

    func testOverridePersistsAcrossInstances() {
        let first = LocalizationService()
        first.override = .simplifiedChinese

        let second = LocalizationService()
        XCTAssertEqual(second.override, .simplifiedChinese)
        XCTAssertEqual(second.effectiveLocale?.identifier, "zh-Hans")
    }

    func testEveryOverrideHasLocalizationKey() {
        for option in LocalizationService.LanguageOverride.allCases {
            XCTAssertFalse(option.localizationKey.isEmpty)
        }
    }
}

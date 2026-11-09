import XCTest
@testable import Cairn

@MainActor
final class PossessionShowcaseLayoutTests: XCTestCase {
    func testShelvesFollowCategoryOrderAndSortByCostWithUnpricedLast() {
        let house = Possession(name: "House", category: .realEstate, purchasePrice: 500_000, purchaseCurrency: "USD")
        let laptop = Possession(name: "Laptop", category: .electronics, purchasePrice: 2_000, purchaseCurrency: "USD")
        let phone = Possession(name: "Phone", category: .electronics, purchasePrice: 900, purchaseCurrency: "USD")
        let camera = Possession(name: "Camera", category: .electronics, purchasePrice: 1_500, purchaseCurrency: "USD")
        let tablet = Possession(name: "Tablet", category: .electronics, purchasePrice: 5_000, purchaseCurrency: "JPY")
        let costs: [UUID: Decimal] = [house.id: 500_000, laptop.id: 2_000, phone.id: 900, camera.id: 1_500]

        let shelves = PossessionShowcaseLayout.shelves(
            byCategory: [.electronics: [phone, tablet, laptop, camera], .realEstate: [house]]
        ) { costs[$0.id] }

        XCTAssertEqual(shelves.map(\.category), [.realEstate, .electronics])
        XCTAssertEqual(shelves[0].items.map(\.name), ["House"])
        XCTAssertEqual(shelves[1].items.map(\.name), ["Laptop", "Camera", "Phone", "Tablet"])
    }
}

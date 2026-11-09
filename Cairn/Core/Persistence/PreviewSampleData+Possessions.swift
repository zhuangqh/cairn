#if DEBUG
import Foundation
import SwiftData

/// Sample possessions for previews and `-CairnSampleData` screenshots. Photos
/// come from the DEBUG-only `sample-possession-*` resources (CC0 / public
/// domain; see `docs/sample-photo-credits.md`): transparent PNG cutouts, and
/// one possession with no photo so the placeholder figure is covered too.
extension PreviewSampleData {
    private static func month(_ year: Int, _ month: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    private static func photo(_ name: String) -> Data? {
        Bundle.main.url(forResource: "sample-possession-\(name)", withExtension: "png")
            .flatMap { try? Data(contentsOf: $0) }
    }

    static func populatePossessions(_ context: ModelContext, alice: Member, bob: Member) {
        let samples: [Possession] = [
            Possession(
                name: "Shanghai apartment", category: .realEstate, purchasePrice: 2_800_000,
                purchaseCurrency: "CNY", purchaseDate: month(2019, 6),
                photoData: photo("apartment"), member: alice
            ),
            Possession(
                name: "Lake cabin", category: .realEstate, purchasePrice: 180_000,
                purchaseCurrency: "USD", purchaseDate: month(2021, 9),
                photoData: photo("cabin"), member: bob
            ),
            Possession(
                name: "Family SUV", category: .vehicle, purchasePrice: 38_000,
                purchaseCurrency: "USD", purchaseDate: month(2023, 3),
                photoData: photo("suv"), member: alice
            ),
            Possession(
                name: "MacBook Pro 16", category: .electronics, purchasePrice: 2_499,
                purchaseCurrency: "USD", purchaseDate: month(2024, 11),
                photoData: photo("laptop"), member: alice
            ),
            Possession(
                name: "Fujifilm X-T10", category: .electronics, purchasePrice: 900,
                purchaseCurrency: "EUR", purchaseDate: month(2022, 4),
                photoData: photo("camera"), member: bob
            ),
            Possession(
                name: "iPhone", category: .electronics, purchasePrice: 7_999,
                purchaseCurrency: "CNY", purchaseDate: month(2024, 9),
                photoData: photo("phone"), member: alice
            ),
            Possession(
                name: "Noise-cancelling headphones", category: .electronics, purchasePrice: 349,
                purchaseCurrency: "USD", purchaseDate: month(2023, 12), member: bob
            ),
            Possession(
                name: "Chronograph watch", category: .other, purchasePrice: 9_100,
                purchaseCurrency: "USD", purchaseDate: month(2020, 1),
                photoData: photo("watch"), member: bob
            ),
            Possession(
                name: "Acoustic guitar", category: .other, purchasePrice: 1_800,
                purchaseCurrency: "USD", purchaseDate: month(2018, 8),
                photoData: photo("guitar"), member: alice
            ),
            Possession(
                name: "Old hatchback", category: .vehicle, purchasePrice: 21_000,
                purchaseCurrency: "USD", purchaseDate: month(2015, 5),
                saleDate: month(2023, 2), salePrice: 9_000, member: alice
            )
        ]
        samples.forEach(context.insert)
    }
}
#endif

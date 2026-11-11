import Foundation
import SwiftData

/// Cached FX conversion rate: `1 unit of base == rate × quote`.
///
/// Keyed by `(base, quote, date)`. Uniqueness is enforced at the application layer
/// because CloudKit sync is not compatible with `@Attribute(.unique)`.
@Model
final class FXRate {
    var id: UUID = UUID()
    var base: String = "USD"
    var quote: String = "USD"
    var rate: Decimal = 1
    var date: Date = Date()

    init(base: String, quote: String, rate: Decimal, date: Date = .now) {
        self.id = UUID()
        self.base = base
        self.quote = quote
        self.rate = rate
        self.date = date
    }
}

import Foundation
import SwiftData

/// Cached FX conversion rate: `1 unit of base == rate × quote`.
///
/// Keyed by `(base, quote, date)`. Uniqueness is enforced at the application layer
/// because CloudKit sync is not compatible with `@Attribute(.unique)`.
@Model
public final class FXRate {
    public var id: UUID = UUID()
    public var base: String = "USD"
    public var quote: String = "USD"
    public var rate: Decimal = 1
    public var date: Date = Date()

    public init(base: String, quote: String, rate: Decimal, date: Date = .now) {
        self.id = UUID()
        self.base = base
        self.quote = quote
        self.rate = rate
        self.date = date
    }
}

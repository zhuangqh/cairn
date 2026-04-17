import Foundation
import SwiftData

/// Monthly valuation of a `Holding` in its native currency.
///
/// `periodMonth` is normalized to the first day of the month at 00:00 UTC.
/// Use `Calendar.iso8601Month.normalize(_:)` for consistency across devices.
@Model
public final class Snapshot {
    public var id: UUID = UUID()
    public var periodMonth: Date = Snapshot.defaultPeriod
    public var amount: Decimal = 0
    public var recordedAt: Date = Date()

    @Relationship public var holding: Holding?

    public init(
        periodMonth: Date,
        amount: Decimal,
        holding: Holding? = nil,
        recordedAt: Date = .now
    ) {
        self.id = UUID()
        self.periodMonth = Snapshot.normalize(periodMonth)
        self.amount = amount
        self.holding = holding
        self.recordedAt = recordedAt
    }

    /// Truncate any date to the first instant of its calendar month in UTC.
    public static func normalize(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static var defaultPeriod: Date { normalize(.now) }
}

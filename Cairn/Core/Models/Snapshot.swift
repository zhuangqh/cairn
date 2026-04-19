import Foundation
import SwiftData

/// Valuation of a `Holding` on a specific day in its native currency.
///
/// Historically snapshots were bucketed monthly (normalized to the first of
/// the month). They are now day-granular: `periodMonth` stores the start of
/// the user-selected day in UTC, so multiple snapshots can coexist within
/// the same month on different days.
///
/// The field name is kept as `periodMonth` to preserve on-disk compatibility
/// with existing SwiftData stores; conceptually it is a `periodDate`.
/// `Snapshot.normalize(_:)` continues to return the month key (first of
/// month UTC) and is used by `PortfolioSnapshot` and other monthly
/// aggregations. Use `Snapshot.normalizeDay(_:)` to get the day key.
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
        self.periodMonth = Snapshot.normalizeDay(periodMonth)
        self.amount = amount
        self.holding = holding
        self.recordedAt = recordedAt
    }

    /// Truncate any date to the first instant of its calendar month in UTC.
    /// Used as the month bucket key by `PortfolioSnapshot` and monthly
    /// aggregations.
    public static func normalize(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Truncate any date to the start of its calendar day in UTC. Used as
    /// the uniqueness key for per-holding snapshots.
    public static func normalizeDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.startOfDay(for: date)
    }

    private static var defaultPeriod: Date { normalizeDay(.now) }
}

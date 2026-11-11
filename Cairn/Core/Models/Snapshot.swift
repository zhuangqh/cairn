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
final class Snapshot {
    var id: UUID = UUID()
    var periodMonth: Date = Snapshot.defaultPeriod
    var amount: Decimal = 0
    var recordedAt: Date = Date()

    @Relationship var holding: Holding?

    init(
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
    static func normalize(_ date: Date) -> Date {
        let components = utcCalendar.dateComponents([.year, .month], from: date)
        return utcCalendar.date(from: components) ?? date
    }

    /// Truncate any date to the start of its calendar day in UTC. Used as
    /// the uniqueness key for per-holding snapshots.
    static func normalizeDay(_ date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    private static var defaultPeriod: Date { normalizeDay(.now) }
}

// MARK: - UTC calendar arithmetic

extension Snapshot {
    /// ISO 8601 calendar pinned to UTC: the calendar behind every snapshot
    /// day/month key and the month arithmetic built on those keys.
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// `date` moved by `months` calendar months in UTC (negative goes back).
    static func adding(months: Int, to date: Date) -> Date? {
        utcCalendar.date(byAdding: .month, value: months, to: date)
    }

    /// `monthStart` moved forward one month; `monthStart` itself in the
    /// (theoretical) case the calendar cannot add a month.
    static func nextMonthStart(after monthStart: Date) -> Date {
        adding(months: 1, to: monthStart) ?? monthStart
    }

    /// Last instant of the UTC month containing `date`, expressed as
    /// `startOfNextMonth - 1s` so a `<=` cutoff includes the month's final
    /// day. `nil` only when the calendar cannot add a month.
    static func endOfMonth(containing date: Date) -> Date? {
        adding(months: 1, to: normalize(date))?.addingTimeInterval(-1)
    }
}

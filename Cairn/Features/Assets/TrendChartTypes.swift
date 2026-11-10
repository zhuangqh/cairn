import Foundation

/// Supporting value types for `TrendChartView`. Lifted into a sibling file
/// so the chart view itself stays under SwiftLint's per-file budget while
/// keeping the data shapes close to where they are consumed.

struct SnapshotMarker: Identifiable, Equatable {
    let id: UUID
    let periodMonth: Date
    let amount: Decimal
    var amountDouble: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

struct TrendSelection: Equatable {
    let period: Date
    let amount: Decimal
    var amountDouble: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

struct TrendPoint: Identifiable, Equatable {
    let period: Date
    let amount: Decimal
    var id: Date { period }
    var amountDouble: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

enum TrendRange: CaseIterable, Hashable {
    case sixMonths
    case year
    case twoYears
    case fiveYears

    var months: Int {
        switch self {
        case .sixMonths: return 6
        case .year: return 12
        case .twoYears: return 24
        case .fiveYears: return 60
        }
    }

    var localizationKey: String {
        switch self {
        case .sixMonths: return "assets.trend.range.6m"
        case .year: return "assets.trend.range.1y"
        case .twoYears: return "assets.trend.range.2y"
        case .fiveYears: return "assets.trend.range.5y"
        }
    }
}

/// Y domain rounded up to two significant figures, with gridlines at zero,
/// the midpoint, and the maximum (§5.8).
struct TrendScale {
    let lower: Double
    let upper: Double

    init(points: [TrendPoint]) {
        let values = points.map(\.amountDouble)
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        upper = Self.niceCeiling(max(maxValue, 0))
        lower = minValue < 0 ? -Self.niceCeiling(-minValue) : 0
    }

    var gridValues: [Double] {
        lower < 0 ? [0, lower, upper] : [0, upper / 2, upper]
    }

    private static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        return (value / magnitude * 10).rounded(.up) / 10 * magnitude
    }
}

import SwiftUI
import Charts

// Chart marks and axis ticks for `TrendChartView` (DESIGN.md §5.8), split out
// to keep the view within lint limits.

extension TrendChartView {
    /// Points on the plotted curve for months that have a captured portfolio
    /// snapshot, so the dots sit on the line (on the Dashboard the curve also
    /// includes physical assets).
    func snapshotPoints(points: [TrendPoint], markers: [SnapshotMarker]) -> [TrendPoint] {
        let months = Set(markers.map { Snapshot.normalize($0.periodMonth) })
        return points.filter { months.contains(Snapshot.normalize($0.period)) }
    }

    /// Recorded snapshot months: hollow ink-green dots, or small solid dots
    /// when the range is dense enough that rings would run together.
    @ChartContentBuilder
    func snapshotMarks(
        _ points: [TrendPoint],
        dense: Bool,
        locale: Locale,
        currencyCode: String
    ) -> some ChartContent {
        ForEach(points) { point in
            PointMark(
                x: .value("assets.trend.axis.month", point.period),
                y: .value("assets.trend.axis.amount", point.amountDouble)
            )
            .symbol {
                if dense {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 4, height: 4)
                } else {
                    SnapshotDot()
                }
            }
            .accessibilityLabel(Text(point.period, format: .dateTime.year().month(.wide).locale(locale)))
            .accessibilityValue(Text(
                point.amount,
                format: .currency(code: currencyCode).precision(.fractionLength(0)).locale(locale)
            ))
        }
    }

    /// Brass "now" dot ringed with the page ground.
    @ChartContentBuilder
    func endMark(_ points: [TrendPoint]) -> some ChartContent {
        if let last = points.last {
            PointMark(
                x: .value("assets.trend.axis.month", last.period),
                y: .value("assets.trend.axis.amount", last.amountDouble)
            )
            .symbol {
                Circle()
                    .fill(Color.brass)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.pageBackground, lineWidth: 2))
            }
        }
    }

    // MARK: - Axis ticks

    /// First, middle, and last periods — at most three ticks so labels never
    /// collide; first/last hug the plot edges.
    func xTicks(_ points: [TrendPoint]) -> [Date] {
        guard let first = points.first?.period, let last = points.last?.period else { return [] }
        if points.count < 3 { return first == last ? [first] : [first, last] }
        return [first, points[points.count / 2].period, last]
    }

    func tickAnchor(index: Int, count: Int) -> UnitPoint {
        if count > 1, index == 0 { return .topLeading }
        if count > 1, index == count - 1 { return .topTrailing }
        return .top
    }

    /// Year + month for the first tick and whenever the year changes from
    /// the previous tick; month alone otherwise.
    func tickLabel(_ date: Date, ticks: [Date], locale: Locale) -> String {
        let calendar = Calendar.current
        let index = ticks.firstIndex(of: date) ?? 0
        let showYear = index == 0
            || calendar.component(.year, from: ticks[index - 1]) != calendar.component(.year, from: date)
        return showYear
            ? date.formatted(.dateTime.year().month(.abbreviated).locale(locale))
            : date.formatted(.dateTime.month(.abbreviated).locale(locale))
    }
}

/// Hollow snapshot marker (§5.8), shared by the chart and its legend.
struct SnapshotDot: View {
    var body: some View {
        Circle()
            .fill(Color.pageBackground)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(Color.accent, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

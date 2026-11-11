import SwiftUI
import Charts

/// Axis header + chart for `TrendChartView`. Owns the hover selection so
/// hover updates re-render only this view, not the parent's data
/// fingerprint and cache.
struct TrendChartPlot: View {
    @Environment(\.locale) private var locale

    let points: [TrendPoint]
    let scale: TrendScale
    let markers: [SnapshotMarker]
    let possessionByPeriod: [Date: Decimal]
    let homeCurrency: String
    let showPossessionOverlay: Bool
    let onSelectionChange: ((TrendSelection?) -> Void)?

    @State private var hoverSelection: TrendSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            axisHeader
            chart
        }
        .onChange(of: hoverSelection) { _, newValue in
            onSelectionChange?(newValue)
        }
    }

    /// Max-value label at top-left; hovered month (or "month-end") at right.
    private var axisHeader: some View {
        HStack {
            Text(verbatim: compactAxisLabel(scale.upper))
            Spacer(minLength: 8)
            if let selection = hoverSelection {
                Text(selection.period, format: .dateTime.year().month(.wide).locale(locale))
            } else {
                HStack(spacing: 10) {
                    if !markers.isEmpty {
                        HStack(spacing: 4) {
                            SnapshotDot()
                            Text("dashboard.trend.snapshot")
                        }
                    }
                    Text("dashboard.trend.monthEnd")
                }
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(Color.ink3)
        .accessibilityHidden(true)
    }

    private func compactAxisLabel(_ value: Double) -> String {
        let symbol = CurrencyAmountParts(0, code: homeCurrency, locale: locale).symbol
        return symbol + value.formatted(.number.notation(.compactName).locale(locale))
    }

    private var chart: some View {
        let ticks = xTicks(points)
        return Chart {
            trendMarks(points)
            snapshotMarks(
                snapshotPoints(points: points, markers: markers),
                dense: points.count > 24,
                locale: locale,
                currencyCode: homeCurrency
            )
            endMark(points)
            hoverMarks
        }
        .chartYScale(domain: scale.lower...scale.upper)
        .chartYAxis {
            AxisMarks(values: scale.gridValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: value.index == 0 ? 1 : 0.7))
                    .foregroundStyle(Color.line)
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel(anchor: tickAnchor(index: value.index, count: value.count)) {
                    if let date = value.as(Date.self) {
                        Text(verbatim: tickLabel(date, ticks: ticks, locale: locale))
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                hoverOverlay(proxy: proxy, geo: geo)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 196)
        .accessibilityLabel(Text(LocalizedStringKey(showPossessionOverlay ? "dashboard.trend" : "assets.trend")))
    }

    @ViewBuilder
    private func hoverOverlay(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotFrameAnchor = proxy.plotFrame {
            let plot = geo[plotFrameAnchor]
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: plot.width, height: plot.height)
                .offset(x: plot.minX, y: plot.minY)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let relativeX = location.x - plot.minX
                        guard relativeX >= 0, relativeX <= plot.width,
                              let date: Date = proxy.value(atX: relativeX) else {
                            hoverSelection = nil
                            return
                        }
                        hoverSelection = nearestSelection(to: date)
                    case .ended:
                        hoverSelection = nil
                    }
                }
                #if os(iOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let relativeX = value.location.x - plot.minX
                            guard relativeX >= 0, relativeX <= plot.width,
                                  let date: Date = proxy.value(atX: relativeX) else { return }
                            hoverSelection = nearestSelection(to: date)
                        }
                        .onEnded { _ in hoverSelection = nil }
                )
                #endif
        }
    }

    @ChartContentBuilder
    private var hoverMarks: some ChartContent {
        if let selection = hoverSelection {
            let possessionAmount = showPossessionOverlay ? possessionByPeriod[selection.period] : nil
            RuleMark(x: .value("assets.trend.axis.month", selection.period))
                .foregroundStyle(Color.ink3.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    hoverCallout(for: selection, possessionAmount: possessionAmount)
                }
            PointMark(
                x: .value("assets.trend.axis.month", selection.period),
                y: .value(
                    "assets.trend.axis.amount",
                    selection.amountDouble + NSDecimalNumber(decimal: possessionAmount ?? 0).doubleValue
                )
            )
            .symbolSize(50)
            .foregroundStyle(Color.accent)
        }
    }

    @ViewBuilder
    private func hoverCallout(for selection: TrendSelection, possessionAmount: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.period, format: .dateTime.year().month(.wide).locale(locale))
                .font(.caption2)
                .foregroundStyle(Color.ink3)
            calloutRow(
                color: .accent,
                labelKey: "dashboard.balance.financial",
                amount: selection.amount
            )
            if let possessionAmount {
                calloutRow(
                    color: .accent2,
                    labelKey: "dashboard.balance.physical",
                    amount: possessionAmount
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.notionSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func calloutRow(color: Color, labelKey: LocalizedStringKey, amount: Decimal) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(labelKey)
                .font(.caption2)
                .foregroundStyle(Color.ink2)
            Text(amount.formatted(.currency(code: homeCurrency).precision(.fractionLength(0)).locale(locale)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
    }

    private func nearestSelection(to date: Date) -> TrendSelection? {
        // Only actual snapshot points are hoverable. Snap to the nearest marker,
        // but only when the cursor is within ~half a month of it so the user has
        // to intentionally land on a point.
        guard !markers.isEmpty else { return nil }
        let nearest = markers.min { lhs, rhs in
            abs(lhs.periodMonth.timeIntervalSince(date)) < abs(rhs.periodMonth.timeIntervalSince(date))
        }
        guard let nearest else { return nil }
        let snapWindow: TimeInterval = 60 * 60 * 24 * 20 // ~20 days
        guard abs(nearest.periodMonth.timeIntervalSince(date)) <= snapWindow else { return nil }
        return TrendSelection(period: nearest.periodMonth, amount: nearest.amount)
    }

    /// Monotone line (2.2pt accent) over a flat 10% accent fill.
    @ChartContentBuilder
    private func trendMarks(_ points: [TrendPoint]) -> some ChartContent {
        ForEach(points) { point in
            AreaMark(
                x: .value("assets.trend.axis.month", point.period),
                y: .value("assets.trend.axis.amount", point.amountDouble)
            )
            .foregroundStyle(Color.accent.opacity(0.10))
            .interpolationMethod(.monotone)
            LineMark(
                x: .value("assets.trend.axis.month", point.period),
                y: .value("assets.trend.axis.amount", point.amountDouble)
            )
            .foregroundStyle(Color.accent)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
    }
}

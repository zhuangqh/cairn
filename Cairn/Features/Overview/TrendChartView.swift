import SwiftUI
import SwiftData
import Charts

/// Monthly net-worth trend line. Drives off `NetWorthCalculator.trend(...)`
/// and updates whenever any upstream model changes.
struct TrendChartView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    // Invalidation sentinels — querying these forces the view to recompute
    // when snapshots/rates/holdings change.
    @Query private var snapshots: [Snapshot]
    @Query private var rates: [FXRate]
    @Query private var holdings: [Holding]
    @Query(sort: \PortfolioSnapshot.periodMonth)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @State private var range: TrendRange = .year
    @State private var hoverSelection: TrendSelection?

    /// Optional observer fired whenever the hover selection changes.
    /// Used by the Dashboard to drive time-travel on the hero / allocation cards.
    var onSelectionChange: ((TrendSelection?) -> Void)?

    init(onSelectionChange: ((TrendSelection?) -> Void)? = nil) {
        self.onSelectionChange = onSelectionChange
    }

    /// Title + hover month + range picker. Rendered in a single row at wide
    /// widths; stacked into two rows at narrow widths so the segmented
    /// picker doesn't squeeze the title.
    @ViewBuilder
    private func header(stacked: Bool) -> some View {
        let title = HStack(spacing: 8) {
            Text("overview.trend")
                .font(.headline)
            // Reserve space for the hover month so the header never jitters.
            Text(hoverSelection.map {
                $0.period.formatted(.dateTime.year().month(.wide).locale(locale))
            } ?? " ")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .animation(.easeOut(duration: 0.12), value: hoverSelection)
        }

        let picker = Picker(selection: $range) {
            ForEach(TrendRange.allCases, id: \.self) { option in
                Text(LocalizedStringKey(option.localizationKey)).tag(option)
            }
        } label: {
            Text("overview.trend.range")
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if stacked {
            VStack(alignment: .leading, spacing: 8) {
                title
                picker.frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 12)
                picker.frame(maxWidth: 280)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                header(stacked: false)
                header(stacked: true)
            }

            let points = trendPoints()
            let markers = snapshotMarkers(windowStart: points.first?.period)
            if points.filter({ $0.amount > 0 }).isEmpty && markers.isEmpty {
                ContentUnavailableView(
                    "overview.trend.empty.title",
                    systemImage: "chart.xyaxis.line",
                    description: Text("overview.trend.empty.hint")
                )
                .frame(minHeight: 220)
            } else {
                chart(for: points, markers: markers)
            }
        }
        .onChange(of: hoverSelection) { _, newValue in
            onSelectionChange?(newValue)
        }
    }

    @ViewBuilder
    private func chart(for points: [TrendPoint], markers: [SnapshotMarker]) -> some View {
        Chart {
            trendMarks(points)
            snapshotMarks(markers)
            hoverMarks()
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formatted(.currency(code: homeCurrency).locale(locale).precision(.fractionLength(0))))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: max(1, points.count / 6))) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.year(.twoDigits).month(.abbreviated).locale(locale))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                hoverOverlay(proxy: proxy, geo: geo, points: points, markers: markers)
            }
        }
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private func hoverOverlay(
        proxy: ChartProxy,
        geo: GeometryProxy,
        points: [TrendPoint],
        markers: [SnapshotMarker]
    ) -> some View {
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
                        hoverSelection = nearestSelection(to: date, points: points, markers: markers)
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
                            hoverSelection = nearestSelection(to: date, points: points, markers: markers)
                        }
                        .onEnded { _ in hoverSelection = nil }
                )
                #endif
        }
    }

    @ChartContentBuilder
    private func hoverMarks() -> some ChartContent {
        if let selection = hoverSelection {
            RuleMark(x: .value("overview.trend.axis.month", selection.period))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    hoverCallout(for: selection)
                }
            PointMark(
                x: .value("overview.trend.axis.month", selection.period),
                y: .value("overview.trend.axis.amount", selection.amountDouble)
            )
            .symbolSize(60)
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func hoverCallout(for selection: TrendSelection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selection.period, format: .dateTime.year().month(.wide).locale(locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(selection.amount.formatted(.currency(code: homeCurrency).locale(locale)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private func nearestSelection(
        to date: Date,
        points: [TrendPoint],
        markers: [SnapshotMarker]
    ) -> TrendSelection? {
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

    @ChartContentBuilder
    private func trendMarks(_ points: [TrendPoint]) -> some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("overview.trend.axis.month", point.period),
                y: .value("overview.trend.axis.amount", point.amountDouble)
            )
            .interpolationMethod(.monotone)
            AreaMark(
                x: .value("overview.trend.axis.month", point.period),
                y: .value("overview.trend.axis.amount", point.amountDouble)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func snapshotMarks(_ markers: [SnapshotMarker]) -> some ChartContent {
        ForEach(markers) { marker in
            PointMark(
                x: .value("overview.trend.axis.month", marker.periodMonth),
                y: .value("overview.trend.axis.amount", marker.amountDouble)
            )
            .symbol(.circle)
            .symbolSize(90)
            .foregroundStyle(Color.accentColor)
            .annotation(position: .top, alignment: .center, spacing: 2) {
                Image(systemName: "camera.aperture")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func trendPoints() -> [TrendPoint] {
        // Touch queries so @Query changes invalidate recomputation.
        _ = snapshots.count + rates.count + holdings.count
        let raw = NetWorthCalculator.trend(
            homeCurrency: homeCurrency,
            months: range.months,
            context: context
        )
        return raw.map { TrendPoint(period: $0.period, amount: $0.amount) }
    }

    private func snapshotMarkers(windowStart: Date?) -> [SnapshotMarker] {
        _ = portfolioSnapshots.count
        guard let windowStart else { return [] }
        return portfolioSnapshots
            .filter { $0.periodMonth >= windowStart && $0.homeCurrency == homeCurrency }
            .map { SnapshotMarker(id: $0.id, periodMonth: $0.periodMonth, amount: $0.totalAmount) }
    }
}

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
        case .sixMonths: return "overview.trend.range.6m"
        case .year: return "overview.trend.range.1y"
        case .twoYears: return "overview.trend.range.2y"
        case .fiveYears: return "overview.trend.range.5y"
        }
    }
}

#Preview {
    let container = PreviewSampleData.container()
    return TrendChartView()
        .padding()
        .modelContainer(container)
}

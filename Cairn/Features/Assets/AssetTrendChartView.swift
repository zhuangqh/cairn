import SwiftUI
import SwiftData
import Charts

/// Cumulative asset-purchase timeline. Each marker on the curve is the
/// `purchaseDate` of an `Asset`; the line traces the running total of
/// acquired value (converted to the home currency).
///
/// Visual language matches `TrendChartView` so the Assets tab and Financial
/// tab inside `OverviewView` feel like a coherent pair — same card padding,
/// same hover callout, same area gradient — with a green palette instead
/// of the accent color to distinguish physical assets from financial ones.
struct AssetTrendChartView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query(sort: \Asset.purchaseDate) private var assets: [Asset]
    @Query private var rates: [FXRate]

    @State private var hoverSelection: AssetTrendSelection?
    @State private var range: TrendRange = .year

    /// Cache of the cumulative-purchase point series. Keyed by a
    /// fingerprint that excludes `hoverSelection` so cursor movement does
    /// not re-derive the timeline.
    @State private var cachedFingerprint: Int = 0
    @State private var cachedPoints: [AssetTrendPoint] = []
    @State private var hasComputed: Bool = false

    /// The accent for this chart. Intentionally green to echo the PRD's
    /// "physical assets" category color and to visually separate it from
    /// the blue/accent financial trend.
    private let lineColor: Color = .green

    var body: some View {
        let fingerprint = currentFingerprint()
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                header(stacked: false)
                header(stacked: true)
            }

            let pts = cachedPoints
            if hasComputed && pts.isEmpty {
                ContentUnavailableView(
                    "asset.trend.empty.title",
                    systemImage: "chart.xyaxis.line",
                    description: Text("asset.trend.empty.hint")
                )
                .frame(minHeight: 220)
            } else {
                chart(for: pts)
            }
        }
        .onAppear { refreshCacheIfNeeded(fingerprint) }
        .onChange(of: fingerprint) { _, new in refreshCacheIfNeeded(new) }
    }

    private func currentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(homeCurrency)
        hasher.combine(range)
        for asset in assets.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(asset.id)
            hasher.combine(asset.name)
            hasher.combine(asset.purchaseDate)
            hasher.combine(asset.purchaseCurrency)
            hasher.combine(NSDecimalNumber(decimal: asset.purchasePrice).stringValue)
        }
        for rate in rates.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(rate.id)
            hasher.combine(rate.base)
            hasher.combine(rate.quote)
            hasher.combine(NSDecimalNumber(decimal: rate.rate).stringValue)
            hasher.combine(rate.date)
        }
        return hasher.finalize()
    }

    private func refreshCacheIfNeeded(_ fingerprint: Int) {
        guard !hasComputed || fingerprint != cachedFingerprint else { return }
        cachedPoints = points()
        cachedFingerprint = fingerprint
        hasComputed = true
    }

    // MARK: - Header

    @ViewBuilder
    private func header(stacked: Bool) -> some View {
        let title = HStack(spacing: 8) {
            Text("asset.trend")
                .font(.headline)
            // Hover date (reserve space to avoid jitter).
            Text(hoverSelection.map {
                $0.date.formatted(.dateTime.year().month(.wide).day().locale(locale))
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
            // Pin the picker to a fixed trailing width so hover-date
            // text changes only reflow the title side — the range bar
            // stays put while the cursor moves over the chart.
            HStack(spacing: 8) {
                title
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)
                picker
                    .frame(width: 280)
                    .layoutPriority(1)
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(for pts: [AssetTrendPoint]) -> some View {
        Chart {
            trendMarks(pts)
            purchaseMarks(pts)
            hoverMarks()
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(CompactCurrencyFormatter.string(
                            amount: Decimal(amount),
                            code: homeCurrency,
                            locale: locale
                        ))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: max(1, xAxisStrideMonths(for: pts)))) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.year(.twoDigits).month(.abbreviated).locale(locale))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                hoverOverlay(proxy: proxy, geo: geo, points: pts)
            }
        }
        .frame(minHeight: 220)
    }

    @ChartContentBuilder
    private func trendMarks(_ pts: [AssetTrendPoint]) -> some ChartContent {
        ForEach(pts) { point in
            LineMark(
                x: .value("overview.trend.axis.month", point.date),
                y: .value("overview.trend.axis.amount", point.cumulativeDouble)
            )
            .foregroundStyle(lineColor)
            .interpolationMethod(.monotone)

            AreaMark(
                x: .value("overview.trend.axis.month", point.date),
                y: .value("overview.trend.axis.amount", point.cumulativeDouble)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [lineColor.opacity(0.3), lineColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func purchaseMarks(_ pts: [AssetTrendPoint]) -> some ChartContent {
        // Skip synthetic boundary anchors (empty assetName) — only show
        // dot markers for real asset purchases.
        ForEach(pts.filter { !$0.assetName.isEmpty }) { point in
            PointMark(
                x: .value("overview.trend.axis.month", point.date),
                y: .value("overview.trend.axis.amount", point.cumulativeDouble)
            )
            .symbol(.circle)
            .symbolSize(36)
            .foregroundStyle(lineColor)
        }
    }

    @ChartContentBuilder
    private func hoverMarks() -> some ChartContent {
        if let sel = hoverSelection {
            RuleMark(x: .value("overview.trend.axis.month", sel.date))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    hoverCallout(for: sel)
                }
            PointMark(
                x: .value("overview.trend.axis.month", sel.date),
                y: .value("overview.trend.axis.amount", sel.cumulativeDouble)
            )
            .symbolSize(60)
            .foregroundStyle(lineColor)
        }
    }

    @ViewBuilder
    private func hoverCallout(for sel: AssetTrendSelection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: sel.assetName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(sel.date, format: .dateTime.year().month(.wide).day().locale(locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(sel.cumulative.formatted(.currency(code: homeCurrency).locale(locale)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.notionSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    // MARK: - Hover plumbing

    @ViewBuilder
    private func hoverOverlay(
        proxy: ChartProxy,
        geo: GeometryProxy,
        points: [AssetTrendPoint]
    ) -> some View {
        if let plotAnchor = proxy.plotFrame {
            let plot = geo[plotAnchor]
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
                        hoverSelection = nearest(to: date, points: points)
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
                            hoverSelection = nearest(to: date, points: points)
                        }
                        .onEnded { _ in hoverSelection = nil }
                )
                #endif
        }
    }

    private func nearest(to date: Date, points: [AssetTrendPoint]) -> AssetTrendSelection? {
        // Only real purchase points are hoverable (skip synthetic anchors).
        let real = points.filter { !$0.assetName.isEmpty }
        guard !real.isEmpty else { return nil }
        let nearest = real.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        guard let nearest else { return nil }
        // Snap window (~20 days) — matches TrendChartView so hover only
        // activates when the cursor is close to an actual data point.
        let snapWindow: TimeInterval = 60 * 60 * 24 * 20
        guard abs(nearest.date.timeIntervalSince(date)) <= snapWindow else { return nil }
        return AssetTrendSelection(
            date: nearest.date,
            cumulative: nearest.cumulative,
            assetName: nearest.assetName
        )
    }

    // MARK: - Data

    private func points() -> [AssetTrendPoint] {
        // Touch @Query results so changes invalidate the view.
        _ = rates.count + assets.count

        // Build the FX rate cache once for the whole pass — avoids one
        // SwiftData fetch per asset's currency conversion.
        let cache = FXService.RateCache.load(in: context)

        let sorted = assets.sorted { $0.purchaseDate < $1.purchaseDate }
        var running: Decimal = 0
        var all: [AssetTrendPoint] = []
        all.reserveCapacity(sorted.count)
        for asset in sorted {
            let converted: Decimal
            if asset.purchaseCurrency == homeCurrency {
                converted = asset.purchasePrice
            } else if let fx = cache.convert(
                amount: asset.purchasePrice,
                from: asset.purchaseCurrency,
                to: homeCurrency
            ) {
                converted = fx
            } else {
                // Missing FX rate — skip contribution but keep the point
                // visible on the timeline at the prior running total so
                // the curve doesn't lose the purchase event entirely.
                converted = 0
            }
            running += converted
            all.append(AssetTrendPoint(
                id: asset.id,
                date: asset.purchaseDate,
                cumulative: running,
                assetName: asset.name
            ))
        }

        // Clip to the selected range window and add boundary anchor points
        // so the X-axis always spans the full selected range — matching the
        // Financial tab's TrendChartView which generates one point per month.
        let cal = Calendar.current
        let now = Date()
        guard let cutoff = cal.date(byAdding: .month, value: -range.months, to: now) else {
            return all
        }

        // Cumulative total of all purchases before the cutoff → the Y value
        // at the left edge of the window.
        let preCutoffTotal = all.last(where: { $0.date < cutoff })?.cumulative ?? 0
        var windowed = all.filter { $0.date >= cutoff }

        // Anchor at the window start so the chart begins at the cutoff date.
        if windowed.first?.date != cutoff {
            windowed.insert(
                AssetTrendPoint(
                    id: AssetTrendPoint.windowStartAnchorID,
                    date: cutoff,
                    cumulative: preCutoffTotal,
                    assetName: ""
                ),
                at: 0
            )
        }

        // Anchor at "now" so the chart extends to the present day.
        let finalTotal = windowed.last?.cumulative ?? 0
        if let lastDate = windowed.last?.date, lastDate < now {
            windowed.append(
                AssetTrendPoint(
                    id: AssetTrendPoint.nowAnchorID,
                    date: now,
                    cumulative: finalTotal,
                    assetName: ""
                )
            )
        }

        return windowed
    }

    /// Pick a reasonable month stride so the axis has ~6 tick labels.
    private func xAxisStrideMonths(for pts: [AssetTrendPoint]) -> Int {
        guard let first = pts.first?.date, let last = pts.last?.date, first < last else {
            return 1
        }
        let cal = Calendar.current
        let months = cal.dateComponents([.month], from: first, to: last).month ?? 0
        return max(1, months / 6)
    }
}

struct AssetTrendPoint: Identifiable, Equatable {
    static let windowStartAnchorID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let nowAnchorID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))

    let id: UUID
    let date: Date
    let cumulative: Decimal
    let assetName: String
    var cumulativeDouble: Double { NSDecimalNumber(decimal: cumulative).doubleValue }
}

struct AssetTrendSelection: Equatable {
    let date: Date
    let cumulative: Decimal
    let assetName: String
    var cumulativeDouble: Double { NSDecimalNumber(decimal: cumulative).doubleValue }
}

#if DEBUG
#Preview {
    let container = PreviewSampleData.container()
    return AssetTrendChartView()
        .padding()
        .modelContainer(container)
}
#endif

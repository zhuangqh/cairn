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
    @Query private var assets: [Asset]
    @Query(sort: \PortfolioSnapshot.periodMonth)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @State private var range: TrendRange = .year
    @State private var hoverSelection: TrendSelection?

    /// Cache of the heavy data series. The cache key intentionally excludes
    /// `hoverSelection` so hovering — which fires many state updates per
    /// second and re-runs `body` — never re-derives the trend, snapshot
    /// markers, or asset overlay. The cache refreshes on `onAppear` and
    /// whenever `cacheFingerprint` changes (range, currency, or any
    /// upstream model count).
    @State private var cachedFingerprint: Int = 0
    @State private var cachedPoints: [TrendPoint] = []
    @State private var cachedMarkers: [SnapshotMarker] = []
    @State private var cachedAssetSeries: [Date: Decimal] = [:]
    @State private var hasComputed: Bool = false

    /// Optional observer fired whenever the hover selection changes.
    /// Used by the Dashboard to drive time-travel on the hero / allocation cards.
    var onSelectionChange: ((TrendSelection?) -> Void)?

    /// When `true`, overlays a green cumulative-physical-asset line on top
    /// of the financial trend. Only the financial (snapshot) points remain
    /// hoverable; the hover callout gains an extra row showing the asset
    /// total at the selected month. Used by the Dashboard to give a single
    /// "combined wealth over time" view while keeping the financial story
    /// authoritative for time-travel.
    let showAssetOverlay: Bool

    init(
        showAssetOverlay: Bool = false,
        onSelectionChange: ((TrendSelection?) -> Void)? = nil
    ) {
        self.showAssetOverlay = showAssetOverlay
        self.onSelectionChange = onSelectionChange
    }

    /// Title + hover month + range picker. Rendered in a single row at wide
    /// widths; stacked into two rows at narrow widths so the segmented
    /// picker doesn't squeeze the title.
    @ViewBuilder
    private func header(stacked: Bool) -> some View {
        let title = HStack(spacing: 8) {
            Text(LocalizedStringKey(showAssetOverlay ? "dashboard.trend" : "overview.trend"))
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
        let fingerprint = currentFingerprint()
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                header(stacked: false)
                header(stacked: true)
            }

            let points = cachedPoints
            let markers = cachedMarkers
            let assetByPeriod = cachedAssetSeries
            if hasComputed
                && points.filter({ $0.amount > 0 }).isEmpty
                && markers.isEmpty
                && assetByPeriod.values.allSatisfy({ $0 == 0 }) {
                ContentUnavailableView(
                    "overview.trend.empty.title",
                    systemImage: "chart.xyaxis.line",
                    description: Text("overview.trend.empty.hint")
                )
                .frame(minHeight: 220)
            } else {
                chart(for: points, markers: markers, assetByPeriod: assetByPeriod)
            }
        }
        .onAppear { refreshCacheIfNeeded(fingerprint) }
        .onChange(of: fingerprint) { _, new in refreshCacheIfNeeded(new) }
        .onChange(of: hoverSelection) { _, newValue in
            onSelectionChange?(newValue)
        }
    }

    /// Hash of every input that affects the chart's data series. Excluding
    /// `hoverSelection` is the whole point — it means moving the cursor
    /// over the chart never re-derives the trend.
    private func currentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(homeCurrency)
        hasher.combine(range)
        hasher.combine(showAssetOverlay)
        hasher.combine(snapshots.count)
        hasher.combine(rates.count)
        hasher.combine(holdings.count)
        hasher.combine(assets.count)
        hasher.combine(portfolioSnapshots.count)
        return hasher.finalize()
    }

    private func refreshCacheIfNeeded(_ fingerprint: Int) {
        guard !hasComputed || fingerprint != cachedFingerprint else { return }
        let points = trendPoints()
        cachedPoints = points
        cachedMarkers = snapshotMarkers(windowStart: points.first?.period)
        cachedAssetSeries = assetSeries(for: points)
        cachedFingerprint = fingerprint
        hasComputed = true
    }

    @ViewBuilder
    private func chart(
        for points: [TrendPoint],
        markers: [SnapshotMarker],
        assetByPeriod: [Date: Decimal]
    ) -> some View {
        Chart {
            trendMarks(points)
            assetOverlayMarks(points: points, assetByPeriod: assetByPeriod)
            snapshotMarks(markers)
            hoverMarks(assetByPeriod: assetByPeriod)
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
        .chartLegend(.hidden)
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
    private func hoverMarks(assetByPeriod: [Date: Decimal]) -> some ChartContent {
        if let selection = hoverSelection {
            let assetAmount = showAssetOverlay ? assetByPeriod[selection.period] : nil
            RuleMark(x: .value("overview.trend.axis.month", selection.period))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    hoverCallout(for: selection, assetAmount: assetAmount)
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
    private func hoverCallout(for selection: TrendSelection, assetAmount: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.period, format: .dateTime.year().month(.wide).locale(locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
            calloutRow(
                color: .accentColor,
                labelKey: "dashboard.balance.financial",
                amount: selection.amount
            )
            if let assetAmount {
                calloutRow(
                    color: .green,
                    labelKey: "dashboard.balance.physical",
                    amount: assetAmount
                )
            }
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

    @ViewBuilder
    private func calloutRow(color: Color, labelKey: LocalizedStringKey, amount: Decimal) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(labelKey)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(amount.formatted(.currency(code: homeCurrency).locale(locale)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
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

    /// Green cumulative-asset overlay. Rendered behind the snapshot markers
    /// but above the financial area so the two curves read as siblings.
    /// Points carry no hover target — only the financial snapshots are
    /// hoverable; the asset value at the selected month surfaces through
    /// the shared callout.
    @ChartContentBuilder
    private func assetOverlayMarks(
        points: [TrendPoint],
        assetByPeriod: [Date: Decimal]
    ) -> some ChartContent {
        if showAssetOverlay, !assetByPeriod.isEmpty {
            ForEach(points) { point in
                let amount = assetByPeriod[point.period] ?? 0
                let y = NSDecimalNumber(decimal: amount).doubleValue
                LineMark(
                    x: .value("overview.trend.axis.month", point.period),
                    y: .value("overview.trend.axis.amount", y),
                    series: .value("series", "asset")
                )
                .foregroundStyle(Color.green)
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("overview.trend.axis.month", point.period),
                    y: .value("overview.trend.axis.amount", y),
                    series: .value("series", "asset")
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.green.opacity(0.22), Color.green.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
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
            .symbolSize(36)
            .foregroundStyle(Color.accentColor)
            .annotation(position: .top, alignment: .center, spacing: 2) {
                Image(systemName: "flag.fill")
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

    /// Cumulative converted purchase value at each trend period, keyed by
    /// that period's month anchor. An asset contributes to every period
    /// whose month is `>=` its `purchaseDate`'s month — so the curve is
    /// non-decreasing and reads like a "what did we own by then" timeline.
    /// Sold assets still count because this chart tracks acquisition cost,
    /// not current holdings — matches `AssetTrendChartView`'s semantics.
    private func assetSeries(for points: [TrendPoint]) -> [Date: Decimal] {
        guard showAssetOverlay, !points.isEmpty else { return [:] }
        _ = assets.count + rates.count

        // Pre-load every cached FX rate once so each asset's conversion is
        // an in-memory lookup rather than a per-asset SwiftData fetch.
        let cache = FXService.RateCache.load(in: context)

        // Pre-convert every asset to the home currency and bucket by the
        // first-of-month anchor so we can compare against TrendPoint.period.
        let cal = Calendar.current
        let converted: [(month: Date, amount: Decimal)] = assets.compactMap { asset in
            let value: Decimal
            if asset.purchaseCurrency == homeCurrency {
                value = asset.purchasePrice
            } else if let fx = cache.convert(
                amount: asset.purchasePrice,
                from: asset.purchaseCurrency,
                to: homeCurrency
            ) {
                value = fx
            } else {
                return nil
            }
            let comps = cal.dateComponents([.year, .month], from: asset.purchaseDate)
            guard let anchor = cal.date(from: comps) else { return nil }
            return (anchor, value)
        }

        var result: [Date: Decimal] = [:]
        for point in points {
            var sum: Decimal = 0
            for entry in converted where entry.month <= point.period {
                sum += entry.amount
            }
            result[point.period] = sum
        }
        return result
    }
}

#Preview {
    let container = PreviewSampleData.container()
    return TrendChartView()
        .padding()
        .modelContainer(container)
}

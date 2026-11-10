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
    @Query private var accounts: [Account]
    @Query private var possessions: [Possession]
    @Query(sort: \PortfolioSnapshot.periodMonth)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @State private var range: TrendRange = .year
    @State private var hoverSelection: TrendSelection?

    /// Cache of the heavy data series. The cache key intentionally excludes
    /// `hoverSelection` so hovering — which fires many state updates per
    /// second and re-runs `body` — never re-derives the trend, snapshot
    /// markers, or possession overlay. The cache refreshes on `onAppear` and
    /// whenever `cacheFingerprint` changes (range, currency, or any
    /// upstream model count).
    @State private var cachedFingerprint: Int = 0
    @State private var cachedPoints: [TrendPoint] = []
    @State private var cachedMarkers: [SnapshotMarker] = []
    @State private var cachedPossessionSeries: [Date: Decimal] = [:]
    @State private var hasComputed: Bool = false

    /// Optional observer fired whenever the hover selection changes.
    /// Used by the Dashboard to drive time-travel on the hero / allocation cards.
    var onSelectionChange: ((TrendSelection?) -> Void)?

    /// When `true`, overlays a green cumulative-physical-possession line on top
    /// of the financial trend. Only the financial (snapshot) points remain
    /// hoverable; the hover callout gains an extra row showing the possession
    /// total at the selected month. Used by the Dashboard to give a single
    /// "combined wealth over time" view while keeping the financial story
    /// authoritative for time-travel.
    let showPossessionOverlay: Bool

    init(
        showPossessionOverlay: Bool = false,
        onSelectionChange: ((TrendSelection?) -> Void)? = nil
    ) {
        self.showPossessionOverlay = showPossessionOverlay
        self.onSelectionChange = onSelectionChange
    }

    var body: some View {
        let fingerprint = currentFingerprint()
        return LedgerSection(Text(LocalizedStringKey(showPossessionOverlay ? "dashboard.trend" : "assets.trend"))) {
            LedgerTextPicker(options: TrendRange.allCases, selection: $range) { option in
                Text(LocalizedStringKey(option.localizationKey))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("assets.trend.range"))
        } content: {
            let points = displayPoints
            if hasComputed
                && points.allSatisfy({ $0.amount == 0 })
                && cachedMarkers.isEmpty {
                ContentUnavailableView(
                    "assets.trend.empty.title",
                    systemImage: "chart.xyaxis.line",
                    description: Text("assets.trend.empty.hint")
                )
                .frame(minHeight: 220)
            } else {
                let scale = TrendScale(points: points)
                VStack(alignment: .leading, spacing: 6) {
                    axisHeader(scale: scale)
                    chart(for: points, scale: scale)
                }
            }
        }
        .onAppear { refreshCacheIfNeeded(fingerprint) }
        .onChange(of: fingerprint) { _, new in refreshCacheIfNeeded(new) }
        .onChange(of: hoverSelection) { _, newValue in
            onSelectionChange?(newValue)
        }
    }

    /// Plotted series: on the Dashboard the financial trend plus cumulative
    /// physical purchases (one combined household curve); elsewhere the
    /// financial trend alone.
    private var displayPoints: [TrendPoint] {
        guard showPossessionOverlay else { return cachedPoints }
        return cachedPoints.map { point in
            TrendPoint(period: point.period, amount: point.amount + (cachedPossessionSeries[point.period] ?? 0))
        }
    }

    /// Max-value label at top-left; hovered month (or "month-end") at right.
    private func axisHeader(scale: TrendScale) -> some View {
        HStack {
            Text(verbatim: compactAxisLabel(scale.upper))
            Spacer(minLength: 8)
            if let selection = hoverSelection {
                Text(selection.period, format: .dateTime.year().month(.wide).locale(locale))
            } else {
                Text("dashboard.trend.monthEnd")
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

    /// Hash of every input that affects the chart's data series. Excluding
    /// `hoverSelection` is the whole point — it means moving the cursor
    /// over the chart never re-derives the trend.
    private func currentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(homeCurrency)
        hasher.combine(range)
        hasher.combine(showPossessionOverlay)
        for snapshot in snapshots.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(snapshot.id)
            hasher.combine(snapshot.periodMonth)
            hasher.combine(NSDecimalNumber(decimal: snapshot.amount).stringValue)
            hasher.combine(snapshot.recordedAt)
            hasher.combine(snapshot.holding?.id)
        }
        for rate in rates.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(rate.id)
            hasher.combine(rate.base)
            hasher.combine(rate.quote)
            hasher.combine(NSDecimalNumber(decimal: rate.rate).stringValue)
            hasher.combine(rate.date)
        }
        for holding in holdings.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(holding.id)
            hasher.combine(holding.currency)
            hasher.combine(holding.isArchived)
            hasher.combine(holding.account?.id)
        }
        for account in accounts.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(account.id)
            hasher.combine(account.kindRawValue)
            hasher.combine(account.isArchived)
            hasher.combine(account.member?.id)
        }
        for possession in possessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(possession.id)
            hasher.combine(possession.purchaseDate)
            hasher.combine(possession.purchaseCurrency)
            hasher.combine(NSDecimalNumber(decimal: possession.purchasePrice).stringValue)
        }
        for snapshot in portfolioSnapshots.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(snapshot.id)
            hasher.combine(snapshot.periodMonth)
            hasher.combine(snapshot.homeCurrency)
            hasher.combine(NSDecimalNumber(decimal: snapshot.totalAmount).stringValue)
            hasher.combine(snapshot.recordedAt)
            hasher.combine(snapshot.entriesData)
            hasher.combine(snapshot.ratesData)
        }
        return hasher.finalize()
    }

    private func refreshCacheIfNeeded(_ fingerprint: Int) {
        guard !hasComputed || fingerprint != cachedFingerprint else { return }
        let points = trendPoints()
        cachedPoints = points
        cachedMarkers = snapshotMarkers(windowStart: points.first?.period)
        cachedPossessionSeries = possessionSeries(for: points)
        cachedFingerprint = fingerprint
        hasComputed = true
    }

    private func chart(for points: [TrendPoint], scale: TrendScale) -> some View {
        let markers = cachedMarkers
        let ticks = xTicks(points)
        return Chart {
            trendMarks(points)
            endMark(points)
            hoverMarks(possessionByPeriod: cachedPossessionSeries)
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
                        Text(verbatim: tickLabel(date, ticks: ticks))
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                hoverOverlay(proxy: proxy, geo: geo, points: points, markers: markers)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 196)
        .accessibilityLabel(Text(LocalizedStringKey(showPossessionOverlay ? "dashboard.trend" : "assets.trend")))
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
    private func hoverMarks(possessionByPeriod: [Date: Decimal]) -> some ChartContent {
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

    /// Monotone line (2.2pt accent) over a flat 5% accent fill.
    @ChartContentBuilder
    private func trendMarks(_ points: [TrendPoint]) -> some ChartContent {
        ForEach(points) { point in
            AreaMark(
                x: .value("assets.trend.axis.month", point.period),
                y: .value("assets.trend.axis.amount", point.amountDouble)
            )
            .foregroundStyle(Color.accent.opacity(0.05))
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

    /// Solid end dot ringed with the page ground.
    @ChartContentBuilder
    private func endMark(_ points: [TrendPoint]) -> some ChartContent {
        if let last = points.last {
            PointMark(
                x: .value("assets.trend.axis.month", last.period),
                y: .value("assets.trend.axis.amount", last.amountDouble)
            )
            .symbol {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.pageBackground, lineWidth: 2))
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
    /// that period's month anchor. An possession contributes to every period
    /// whose month is `>=` its `purchaseDate`'s month — so the curve is
    /// non-decreasing and reads like a "what did we own by then" timeline.
    /// Sold possessions still count because this chart tracks acquisition cost,
    /// not current holdings — matches `PossessionTrendChartView`'s semantics.
    private func possessionSeries(for points: [TrendPoint]) -> [Date: Decimal] {
        guard showPossessionOverlay, !points.isEmpty else { return [:] }
        _ = possessions.count + rates.count

        // Pre-load every cached FX rate once so each possession's conversion is
        // an in-memory lookup rather than a per-possession SwiftData fetch.
        let cache = FXService.RateCache.load(in: context)

        // Pre-convert every possession to the home currency and bucket by the
        // first-of-month anchor so we can compare against TrendPoint.period.
        let cal = Calendar.current
        let converted: [(month: Date, amount: Decimal)] = possessions.compactMap { possession in
            let value: Decimal
            if possession.purchaseCurrency == homeCurrency {
                value = possession.purchasePrice
            } else if let fx = cache.convert(
                amount: possession.purchasePrice,
                from: possession.purchaseCurrency,
                to: homeCurrency
            ) {
                value = fx
            } else {
                return nil
            }
            let comps = cal.dateComponents([.year, .month], from: possession.purchaseDate)
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

// MARK: - Axis ticks

extension TrendChartView {
    /// First, middle, and last periods — at most three ticks so labels never
    /// collide; first/last hug the plot edges.
    private func xTicks(_ points: [TrendPoint]) -> [Date] {
        guard let first = points.first?.period, let last = points.last?.period else { return [] }
        if points.count < 3 { return first == last ? [first] : [first, last] }
        return [first, points[points.count / 2].period, last]
    }

    private func tickAnchor(index: Int, count: Int) -> UnitPoint {
        if count > 1, index == 0 { return .topLeading }
        if count > 1, index == count - 1 { return .topTrailing }
        return .top
    }

    /// Year + month for the first tick and whenever the year changes from
    /// the previous tick; month alone otherwise.
    private func tickLabel(_ date: Date, ticks: [Date]) -> String {
        let calendar = Calendar.current
        let index = ticks.firstIndex(of: date) ?? 0
        let showYear = index == 0
            || calendar.component(.year, from: ticks[index - 1]) != calendar.component(.year, from: date)
        return showYear
            ? date.formatted(.dateTime.year().month(.abbreviated).locale(locale))
            : date.formatted(.dateTime.month(.abbreviated).locale(locale))
    }
}

#Preview {
    let container = PreviewSampleData.container()
    return TrendChartView()
        .padding()
        .modelContainer(container)
}

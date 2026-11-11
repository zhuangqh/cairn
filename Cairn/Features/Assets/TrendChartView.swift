import SwiftUI
import SwiftData
import Charts

/// Monthly net-worth trend line. Drives off `NetWorthCalculator.trend(...)`
/// and updates whenever any upstream model changes.
///
/// Hover state lives in `TrendChartPlot`, so moving the cursor over the
/// chart never re-runs this view's `body` (and its data fingerprint).
/// `Equatable` compares only `showPossessionOverlay`: `onSelectionChange`
/// is excluded so a host re-rendering on hover (the Dashboard) with a new
/// closure of the same behavior does not invalidate the chart either.
struct TrendChartView: View, Equatable {
    @Environment(\.modelContext) private var context

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

    /// Cache of the heavy data series. The cache refreshes on `onAppear`
    /// and whenever `currentFingerprint()` changes (range, currency, or any
    /// upstream model value); hover selection lives in `TrendChartPlot` and
    /// never re-derives the trend, snapshot markers, or possession overlay.
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

    nonisolated static func == (lhs: TrendChartView, rhs: TrendChartView) -> Bool {
        lhs.showPossessionOverlay == rhs.showPossessionOverlay
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
                TrendChartPlot(
                    points: points,
                    scale: TrendScale(points: points),
                    markers: cachedMarkers,
                    possessionByPeriod: cachedPossessionSeries,
                    homeCurrency: homeCurrency,
                    showPossessionOverlay: showPossessionOverlay,
                    onSelectionChange: onSelectionChange
                )
            }
        }
        .onAppear { refreshCacheIfNeeded(fingerprint) }
        .onChange(of: fingerprint) { _, new in refreshCacheIfNeeded(new) }
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

    /// Hash of every input that affects the chart's data series. Hover
    /// selection is not an input, so moving the cursor over the chart never
    /// re-derives the trend.
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

        return Self.cumulativeSeries(periods: points.map(\.period), entries: converted)
    }

    /// Running total of `entries` at each period: the sum of every entry
    /// whose month is `<=` that period. Sorts once and walks the periods in
    /// order, instead of re-scanning every entry per period.
    static func cumulativeSeries(
        periods: [Date],
        entries: [(month: Date, amount: Decimal)]
    ) -> [Date: Decimal] {
        let sortedEntries = entries.sorted { $0.month < $1.month }
        var result: [Date: Decimal] = [:]
        result.reserveCapacity(periods.count)
        var sum: Decimal = 0
        var next = sortedEntries.startIndex
        for period in periods.sorted() {
            while next < sortedEntries.endIndex, sortedEntries[next].month <= period {
                sum += sortedEntries[next].amount
                next += 1
            }
            result[period] = sum
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

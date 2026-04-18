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

    @State private var range: TrendRange = .year

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("overview.trend")
                    .font(.headline)
                Spacer()
                Picker(selection: $range) {
                    ForEach(TrendRange.allCases, id: \.self) { option in
                        Text(LocalizedStringKey(option.localizationKey)).tag(option)
                    }
                } label: {
                    Text("overview.trend.range")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
            }

            let points = trendPoints()
            if points.filter({ $0.amount > 0 }).isEmpty {
                ContentUnavailableView(
                    "overview.trend.empty.title",
                    systemImage: "chart.xyaxis.line",
                    description: Text("overview.trend.empty.hint")
                )
                .frame(minHeight: 220)
            } else {
                chart(for: points)
            }
        }
    }

    @ViewBuilder
    private func chart(for points: [TrendPoint]) -> some View {
        Chart(points) { point in
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
        .frame(minHeight: 220)
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

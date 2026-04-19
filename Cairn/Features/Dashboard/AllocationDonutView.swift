import SwiftUI
import Charts

/// Donut-style allocation chart driven by `NetWorthCalculator.KindTotal`
/// entries. Renders a neutral "no data" state when totals are empty.
struct AllocationDonutView: View {
    let entries: [NetWorthCalculator.KindTotal]
    let homeCurrency: String

    @Environment(\.locale) private var locale

    private var total: Decimal {
        entries.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            chart
                .frame(width: 180, height: 180)
            legend
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if entries.isEmpty {
            ZStack {
                Circle().strokeBorder(.secondary.opacity(0.25), lineWidth: 18)
                Image(systemName: "chart.pie")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        } else {
            Chart(entries) { entry in
                SectorMark(
                    angle: .value("dashboard.allocation.axis.amount", entry.amountDouble),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(entry.kind.tint)
                .annotation(position: .overlay) {
                    let value = percentage(for: entry)
                    if value >= 0.05 {
                        Text(value, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 0)
                    }
                }
            }
            .chartLegend(.hidden)
        }
    }

    @ViewBuilder
    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Circle()
                        .fill(entry.kind.tint)
                        .frame(width: 10, height: 10)
                    Text(LocalizedStringKey(entry.kind.localizationKey))
                        .font(.callout)
                    Spacer(minLength: 12)
                    Text(
                        entry.amount,
                        format: .currency(code: homeCurrency)
                            .locale(locale)
                            .precision(.fractionLength(0))
                    )
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func percentage(for entry: NetWorthCalculator.KindTotal) -> Double {
        guard total > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: entry.amount / total).doubleValue
        return ratio
    }
}

private extension NetWorthCalculator.KindTotal {
    var amountDouble: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

extension AccountKind {
    /// Stable display tint used by the donut + category cards.
    var tint: Color {
        switch self {
        case .realEstate: return .blue
        case .stock: return .indigo
        case .cash: return .green
        case .device: return .orange
        }
    }

    var iconName: String {
        switch self {
        case .realEstate: return "house.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .cash: return "banknote.fill"
        case .device: return "laptopcomputer"
        }
    }
}

#Preview("Allocation · populated") {
    AllocationDonutView(
        entries: [
            .init(kind: .realEstate, amount: 450_000),
            .init(kind: .stock, amount: 65_000),
            .init(kind: .cash, amount: 25_000),
            .init(kind: .device, amount: 2_400)
        ],
        homeCurrency: "USD"
    )
    .padding()
}

#Preview("Allocation · empty") {
    AllocationDonutView(entries: [], homeCurrency: "USD")
        .padding()
}

import SwiftUI
import Charts

/// Donut + detailed allocation list. Drives off
/// `NetWorthCalculator.KindTotal` entries plus an optional per-kind
/// month-over-month delta. Each list row shows the localized category
/// name, the converted home-currency value, its share of the total,
/// and (when a baseline exists) the signed change vs last month.
///
/// Layout adapts to width: at wide widths the donut sits on the left
/// with the list on the right; below ~520pt the donut stacks above
/// the list.
struct AllocationDonutView: View {
    let entries: [NetWorthCalculator.KindTotal]
    let homeCurrency: String
    /// Per-kind month-over-month percentage change. Missing keys render
    /// without a delta badge (used for the cold-start case).
    var deltas: [AccountKind: Double] = [:]

    @Environment(\.locale) private var locale
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var total: Decimal {
        entries.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Whether the donut + list should sit side-by-side. We pick this
    /// from the platform / size class instead of measuring the
    /// container, so the card renders with its true intrinsic height
    /// (no `GeometryReader` swallowing it down to a fixed minHeight)
    /// and won't flip layouts mid-interaction when sibling cards
    /// resize on hover.
    private var useHorizontalLayout: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        Group {
            if useHorizontalLayout {
                HStack(alignment: .top, spacing: 28) {
                    chart
                        .frame(width: 168, height: 168)
                    list
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    chart
                        .frame(width: 160, height: 160)
                        .frame(maxWidth: .infinity, alignment: .center)
                    list
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chart: some View {
        if entries.isEmpty {
            ZStack {
                Circle()
                    .strokeBorder(Color.notionBorder, lineWidth: 16)
                Image(systemName: "chart.pie")
                    .font(.title2)
                    .foregroundStyle(Color.notionInkMuted)
            }
        } else {
            Chart(entries) { entry in
                SectorMark(
                    angle: .value("dashboard.allocation.axis.amount", entry.amountDouble),
                    innerRadius: .ratio(0.66),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(entry.kind.tint)
            }
            .chartLegend(.hidden)
        }
    }

    @ViewBuilder
    private var list: some View {
        if entries.isEmpty {
            Text("dashboard.recentActivities.empty")
                .font(.callout)
                .foregroundStyle(Color.notionInkSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(for: entry)
                    if index != entries.count - 1 {
                        Divider()
                            .overlay(Color.notionBorder)
                            .padding(.leading, 22)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: NetWorthCalculator.KindTotal) -> some View {
        let pct = percentage(for: entry)
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(entry.kind.tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(entry.kind.localizationKey))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.notionInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(pct, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color.notionInkSecondary)
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

            // Trailing column hugs its content so the delta badge can
            // grow past +100% without being clipped or truncated.
            VStack(alignment: .trailing, spacing: 2) {
                Text(CompactCurrencyFormatter.string(
                    amount: entry.amount,
                    code: homeCurrency,
                    locale: locale
                ))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.notionInk)
                .lineLimit(1)

                if let delta = deltas[entry.kind] {
                    DeltaBadge(percent: delta)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text(verbatim: " ")
                        .font(.system(size: 11))
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 8)
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
    ///
    /// Palette deliberately avoids the Dashboard's two semantic hues —
    /// Notion Blue (reserved for the Financial balance tile / interactive
    /// accent) and Notion Teal/Green (reserved for the Physical balance
    /// tile + positive trend). The remaining four hues are picked from
    /// opposite sides of the colour wheel so adjacent donut sectors stay
    /// visually distinct on both light and dark surfaces.
    var tint: Color {
        switch self {
        case .cash:       return Color(hex: 0xE89A9A) // Coral pink
        case .stock:      return Color(hex: 0xE0A66E) // Warm apricot
        case .realEstate: return Color(hex: 0x6EB8A8) // Fresh sage
        case .device:     return Color(hex: 0xB39BE8) // Bright periwinkle
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

/// Small signed-percentage badge shared with the Assets screen lives in
/// `AssetsComponents.swift` (`DeltaBadge`). It accepts a `Double?` and is
/// hidden when the baseline is `nil` — exactly the semantics the
/// allocation list and composition card need here.

#Preview("Allocation · populated") {
    AllocationDonutView(
        entries: [
            .init(kind: .realEstate, amount: 450_000),
            .init(kind: .stock, amount: 65_000),
            .init(kind: .cash, amount: 25_000),
            .init(kind: .device, amount: 2_400)
        ],
        homeCurrency: "USD",
        deltas: [.realEstate: 0.012, .stock: -0.034, .cash: 0.0]
    )
    .padding()
}

#Preview("Allocation · empty") {
    AllocationDonutView(entries: [], homeCurrency: "USD")
        .padding()
}

import SwiftUI

/// Dashboard 「资产构成」 body (DESIGN.md §5.3): a two-segment financial /
/// physical bar with its legend, then one row per category — swatch, name,
/// share, and whole-unit amount. Each category keeps its own hue
/// (`AccountKind.tint`) so the swatch matches its account icons everywhere.
struct CompositionBreakdownView: View {
    let financial: Decimal
    let physical: Decimal
    /// Category totals, sorted largest first.
    let entries: [NetWorthCalculator.KindTotal]
    let homeCurrency: String

    @Environment(\.locale) private var locale

    private var total: Decimal { financial + physical }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if total > 0 {
                CompositionBar(
                    firstShare: share(of: financial),
                    firstTitle: Text("dashboard.balance.financial"),
                    secondTitle: Text("dashboard.balance.physical")
                )
                .padding(.top, 6)
                .padding(.bottom, 6)
            }

            if entries.isEmpty {
                Text("dashboard.composition.empty")
                    .font(.callout)
                    .foregroundStyle(Color.ink2)
                    .padding(.vertical, 12)
            } else {
                // Grid so the share and amount columns line up across rows.
                Grid(alignment: .leading, horizontalSpacing: LedgerMetrics.columnSpacing, verticalSpacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { rank, entry in
                        if rank > 0 {
                            LedgerHairline()
                                .padding(.leading, 9 + LedgerMetrics.columnSpacing)
                        }
                        row(for: entry)
                    }
                }
            }
        }
    }

    private func row(for entry: NetWorthCalculator.KindTotal) -> some View {
        let pct = share(of: entry.amount)
        return GridRow {
            LedgerSwatch(color: entry.kind.tint)
            Text(LocalizedStringKey(entry.kind.localizationKey))
                .font(.callout)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Text(pct, format: .percent.precision(.fractionLength(0)))
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.ink3)
                .gridColumnAlignment(.trailing)
            Text(entry.amount, format: .currency(code: homeCurrency).precision(.fractionLength(0)).locale(locale))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .fixedSize()
                .gridColumnAlignment(.trailing)
        }
    }

    private func share(of amount: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: amount / total).doubleValue
    }
}

extension AccountKind {
    /// Category hue from `Color.categoryPalette`, shared by account icons and
    /// the composition swatches.
    var tint: Color {
        switch self {
        case .realEstate: return .accent
        case .stock: return .mist
        case .cash: return .brass
        case .device: return .terracotta
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

#Preview("Composition · populated") {
    CompositionBreakdownView(
        financial: 90_000,
        physical: 452_400,
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

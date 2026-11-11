import SwiftUI

extension PortfolioSnapshotDetailView {
    /// FX impact and manual updates vs the previous snapshot, with the FX
    /// row listing each captured rate change.
    struct ChangeBreakdownCard: View {
        @Environment(\.locale) private var locale

        let breakdown: PortfolioChangeBreakdown
        let homeCurrency: String

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("portfolioSnapshot.detail.change.title")

                let rows = breakdown.displayRows
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        breakdownRow(
                            row,
                            rateChanges: row.id == "fx" ? breakdown.fxRateChanges : []
                        )
                        if index < rows.count - 1 {
                            Divider()
                                .opacity(0.35)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Metrics.cardCornerRadius, padding: Metrics.cardPadding)
        }

        @ViewBuilder
        private func breakdownRow(
            _ row: BreakdownRow,
            rateChanges: [PortfolioChangeBreakdown.FXRateChange]
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.titleKey)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)

                    Text(verbatim: signedAmount(row.amount, currency: homeCurrency, locale: locale))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(ChangeTone.color(for: row.amount, locale: locale))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                }

                Text(row.subtitleKey)
                    .font(.caption)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                if !rateChanges.isEmpty {
                    rateChangesTable(rateChanges)
                }
            }
            .padding(.vertical, 10)
        }

        private func rateChangesTable(_ rateChanges: [PortfolioChangeBreakdown.FXRateChange]) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("portfolioSnapshot.detail.rates")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ink2)
                    Spacer()
                    Text(verbatim: homeCurrency)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)

                Divider().opacity(0.35)

                ForEach(Array(rateChanges.enumerated()), id: \.element.id) { index, change in
                    HStack(spacing: 10) {
                        Text(verbatim: change.currency)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 34, alignment: .leading)

                        Text(verbatim: formattedRate(change.oldRate))
                            .foregroundStyle(Color.ink3)

                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.ink3.opacity(0.65))

                        Text(verbatim: formattedRate(change.newRate))
                            .foregroundStyle(Color.ink)
                            .fontWeight(.medium)

                        Spacer(minLength: 0)
                    }
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)

                    if index < rateChanges.count - 1 {
                        Divider()
                            .opacity(0.22)
                            .padding(.leading, 11)
                    }
                }
            }
            .background(
                Color.notionSurfaceAlt.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }

        private func formattedRate(_ rate: Decimal) -> String {
            rate.formatted(.number.precision(.fractionLength(2...4)).locale(locale))
        }
    }
}

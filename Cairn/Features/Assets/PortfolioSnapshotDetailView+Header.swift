import SwiftUI

extension PortfolioSnapshotDetailView {
    /// Total, signed delta vs the previous snapshot, capture dates, and note.
    struct HeaderCard: View {
        @Environment(\.locale) private var locale
        @Environment(LocalizationService.self) private var localization

        let snapshot: PortfolioSnapshot
        let capturedDate: Date
        let totalDelta: TotalDelta?

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("portfolioSnapshot.detail.total")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text(verbatim: snapshot.homeCurrency)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
                Text(
                    snapshot.totalAmount,
                    format: .currency(code: snapshot.homeCurrency)
                        .precision(.fractionLength(0))
                        .locale(locale)
                )
                    .font(.system(size: 36, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                if let totalDelta {
                    headerDeltaLine(totalDelta)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(
                        "portfolioSnapshot.detail.batchDate \(capturedDate.formatted(footnoteDateFormat.inUTC))"
                    ))
                    Text(LocalizedStringKey(
                        "portfolioSnapshot.detail.capturedAt \(snapshot.recordedAt, format: footnoteDateFormat)"
                    ))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if let note = snapshot.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Metrics.cardCornerRadius, padding: Metrics.cardPadding)
        }

        @ViewBuilder
        private func headerDeltaLine(_ delta: TotalDelta) -> some View {
            let isPositive = delta.amount >= 0
            let tint = ChangeTone.color(for: delta.amount, locale: locale)
            HStack(spacing: 8) {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                Text(verbatim: signedAmount(delta.amount, currency: snapshot.homeCurrency, locale: locale))
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint)
                if let percent = delta.percent {
                    Text(verbatim: "(\(signedPercent(percent)))")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(tint.opacity(0.85))
                }
                Text(verbatim: vsPreviousLabel(delta.previousMonth))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        private func signedPercent(_ value: Double) -> String {
            let isPositive = value >= 0
            let abs = Swift.abs(value)
            let formatted = abs.formatted(.percent.precision(.fractionLength(1)).locale(locale))
            return (isPositive ? "+" : "−") + formatted
        }

        private func vsPreviousLabel(_ previousMonth: Date) -> String {
            let template = String(localized: "portfolioSnapshot.detail.change.vs", bundle: localization.bundle)
            let label = previousMonth.formatted(
                .dateTime.year().month(.abbreviated).locale(locale).inUTC
            )
            return template.replacingOccurrences(of: "{month}", with: label)
        }

        private var footnoteDateFormat: Date.FormatStyle {
            Date.FormatStyle.dateTime.year().month().day().locale(locale)
        }
    }
}

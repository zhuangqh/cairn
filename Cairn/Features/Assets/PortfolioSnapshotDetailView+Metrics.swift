import SwiftUI

// MARK: - Layout metrics

extension PortfolioSnapshotDetailView {
    /// Platform layout constants shared by the detail page's cards and rows.
    enum Metrics {
        #if os(macOS)
        static let pageHorizontalInset: CGFloat = 24
        static let cardPadding: CGFloat = 20
        static let cardCornerRadius: CGFloat = 16
        static let memberAvatarSize: CGFloat = 24
        static let amountBoxWidth: CGFloat = 190
        static let rowSpacing: CGFloat = 12
        static let minimumColumnSpacing: CGFloat = 8
        static let rowVerticalPadding: CGFloat = 9
        #else
        static let pageHorizontalInset: CGFloat = 10
        static let cardPadding: CGFloat = 12
        static let cardCornerRadius: CGFloat = 14
        static let memberAvatarSize: CGFloat = 26
        static let amountBoxWidth: CGFloat = 148
        static let rowSpacing: CGFloat = 8
        static let minimumColumnSpacing: CGFloat = 6
        static let rowVerticalPadding: CGFloat = 8
        #endif
        static let rowGlyphSize: CGFloat = 28
    }
}

// MARK: - Shared pieces

extension PortfolioSnapshotDetailView {
    static func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.ink)
    }

    static func signedAmount(_ value: Decimal, currency: String, locale: Locale) -> String {
        let isPositive = value >= 0
        let abs = value < 0 ? -value : value
        let formatted = abs.formatted(
            .currency(code: currency)
                .locale(locale)
                .precision(.fractionLength(0))
        )
        return (isPositive ? "+" : "−") + formatted
    }

    /// Compact signed delta with a direction arrow, tinted by `ChangeTone`.
    struct InlineDelta: View {
        @Environment(\.locale) private var locale

        let amount: Decimal
        let currency: String

        var body: some View {
            let isPositive = amount >= 0
            let tint = ChangeTone.color(for: amount, locale: locale)
            HStack(spacing: 3) {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.bold))
                Text(verbatim: PortfolioSnapshotDetailView.signedAmount(amount, currency: currency, locale: locale))
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(tint)
        }
    }
}

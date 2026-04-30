import SwiftUI
import SwiftData

// MARK: - Delta badge

/// Compact "↑ +2.9%" / "↓ -1.4%" pill used across the Assets screen.
/// Hidden when `percent` is `nil` (no baseline available).
struct DeltaBadge: View {
    /// Fractional change, e.g. `0.029` → `+2.9%`. `nil` renders nothing.
    let percent: Double?
    /// Optional absolute delta — when supplied, drawn before the percent.
    let amount: Decimal?
    let currencyCode: String
    let locale: Locale

    /// Compact (just the percent) or full ("+¥134,462 (+2.9%)").
    enum Style { case compact, full }
    var style: Style = .compact

    init(
        percent: Double?,
        amount: Decimal? = nil,
        currencyCode: String = "USD",
        locale: Locale = .current,
        style: Style = .compact
    ) {
        self.percent = percent
        self.amount = amount
        self.currencyCode = currencyCode
        self.locale = locale
        self.style = style
    }

    var body: some View {
        if let percent {
            let isPositive = percent >= 0
            let tint: Color = isPositive ? .notionGreen : .notionOrange
            HStack(spacing: 4) {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.bold))
                if style == .full, let amount {
                    Text(verbatim: signedAmount(amount, isPositive: isPositive))
                        .monospacedDigit()
                    Text(verbatim: "(\(percentString(percent, isPositive: isPositive)))")
                        .monospacedDigit()
                        .foregroundStyle(tint.opacity(0.85))
                } else {
                    Text(verbatim: percentString(percent, isPositive: isPositive))
                        .monospacedDigit()
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule(style: .continuous))
        }
    }

    private func percentString(_ value: Double, isPositive: Bool) -> String {
        let abs = Swift.abs(value)
        let formatted = abs.formatted(.percent.precision(.fractionLength(1)))
        return (isPositive ? "+" : "−") + formatted
    }

    private func signedAmount(_ value: Decimal, isPositive: Bool) -> String {
        let abs = value < 0 ? -value : value
        let formatted = abs.formatted(
            .currency(code: currencyCode)
                .locale(locale)
                .precision(.fractionLength(0))
        )
        return (isPositive ? "+" : "−") + formatted
    }
}

// MARK: - Member row

/// Apple-Wallet-flavored row showing a member's contribution to the
/// household net worth: avatar, name, amount, share bar with percent, and
/// month-over-month delta.
struct AssetsMemberRow: View {
    let memberId: UUID
    let memberName: String
    let avatarData: Data?
    let amount: Decimal
    /// 0…1 — share of household total.
    let share: Double
    /// Fractional month-over-month change, or `nil` if no baseline.
    let monthDelta: Double?
    let currencyCode: String
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                MemberAvatarView(
                    name: memberName,
                    avatarData: avatarData,
                    seed: memberId,
                    size: 32
                )
                Text(verbatim: memberName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.notionInk)
                Spacer(minLength: 8)
                Text(
                    amount,
                    format: .currency(code: currencyCode)
                        .locale(locale)
                        .precision(.fractionLength(0))
                )
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.notionInk)
            }

            HStack(spacing: 10) {
                ShareBar(progress: share)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                Text(verbatim: shareString)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
                DeltaBadge(
                    percent: monthDelta,
                    currencyCode: currencyCode,
                    locale: locale
                )
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var shareString: String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Thin proportional bar used inside `AssetsMemberRow`.
private struct ShareBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, geo.size.width * clamped))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Snapshot timeline row

/// Apple-Stocks-meets-timeline row: a small dot + connector line on the
/// leading edge, the period and amount on the trailing side, and a
/// delta-vs-prior-snapshot pill underneath.
struct AssetsSnapshotRow: View {
    let snapshot: PortfolioSnapshot
    /// The chronologically-prior snapshot (older). Used to compute delta.
    let previous: PortfolioSnapshot?
    /// `false` for the last (oldest) row so the connector trails off.
    let isLast: Bool
    /// User's current home currency — used to decide whether to show the
    /// snapshot's own currency badge subtly.
    let homeCurrency: String
    let locale: Locale

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            timelineRail
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: monthLabel)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.notionInk)
                    Spacer(minLength: 8)
                    Text(
                        snapshot.totalAmount,
                        format: .currency(code: snapshot.homeCurrency)
                            .locale(locale)
                            .precision(.fractionLength(0))
                    )
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.notionInk)
                }
                metaRow
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor.opacity(0.9))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 10)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let percent = deltaPercent {
                DeltaBadge(
                    percent: percent,
                    currencyCode: snapshot.homeCurrency,
                    locale: locale
                )
            }
            if let note = snapshot.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if snapshot.homeCurrency != homeCurrency {
                Text(verbatim: snapshot.homeCurrency)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var monthLabel: String {
        snapshot.periodMonth.formatted(
            .dateTime.year().month(.wide).locale(locale)
        )
    }

    private var deltaPercent: Double? {
        guard let prev = previous, prev.totalAmount != 0 else { return nil }
        let change = (snapshot.totalAmount - prev.totalAmount) / prev.totalAmount
        return NSDecimalNumber(decimal: change).doubleValue
    }
}

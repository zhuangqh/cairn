import SwiftUI
import SwiftData

// MARK: - Delta badge

/// Compact direction-arrow change, e.g. `↗ 2.9%` (accent) or `↘ 1.4%` (ink2).
/// Direction is carried by the arrow, so no `+` sign (DESIGN.md §6).
/// Hidden when `percent` is `nil` (no baseline available).
struct DeltaBadge: View {
    /// Fractional change, e.g. `0.029` → `2.9%`. `nil` renders nothing.
    let percent: Double?
    /// Optional absolute delta — when supplied in `.full`, drawn before the percent.
    let amount: Decimal?
    let currencyCode: String
    let locale: Locale

    /// Compact (just the percent) or full (amount + percent).
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
            LedgerDeltaLine(
                amount: style == .full ? amount : nil,
                percent: percent,
                code: currencyCode,
                locale: locale
            )
            .font(.caption.weight(.semibold))
        }
    }
}

// MARK: - Breakdown section + row

/// Titled section shared by the By member / By currency breakdowns and the
/// Possessions category sections: hairline rule, 20pt bold title, optional
/// trailing meta text (e.g. "3 items · ¥120,000").
struct AssetsBreakdownCard<Rows: View>: View {
    let titleKey: LocalizedStringKey
    /// Optional trailing summary in the header.
    var accessory: String?
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        LedgerSection(Text(titleKey)) {
            if let accessory {
                Text(verbatim: accessory)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink3)
            }
        } content: {
            VStack(spacing: 0) {
                rows()
            }
        }
    }
}

/// Progress row used by member, currency, and possession breakdowns: leading
/// mark, name with inline caption, trailing amount, share column, and a meter
/// under the row. Sharing one row type keeps the columns aligned across
/// sections.
struct AssetsBreakdownRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    let title: String
    var caption: String?
    @ViewBuilder let trailing: () -> Trailing
    /// 0…1 share of the household total; `nil` renders an empty meter and "—".
    /// Ignored when `showsShare` is false.
    let share: Double?
    var showsShare: Bool = true
    /// Fractional month-over-month change. Not drawn in the ledger layout;
    /// retained so callers keep a single row API.
    let monthDelta: Double?
    let currencyCode: String
    let locale: Locale

    var body: some View {
        LedgerProgressRow(
            leading: leading,
            title: title,
            caption: caption,
            trailing: trailing,
            share: share,
            showsShare: showsShare
        )
    }
}

/// Home-currency amount shown in the trailing slot of breakdown rows.
struct AssetsBreakdownAmount: View {
    let amount: Decimal
    let currencyCode: String
    let locale: Locale

    var body: some View {
        Text(
            amount,
            format: .currency(code: currencyCode)
                .locale(locale)
                .precision(.fractionLength(0))
        )
    }
}

// MARK: - Member row

/// A member's contribution to household net worth: avatar, name with account
/// count, amount, share, and meter.
struct AssetsMemberRow: View {
    let memberId: UUID
    let memberName: String
    let avatarData: Data?
    var accountCount: Int?
    let amount: Decimal
    /// 0…1 — share of household total.
    let share: Double
    /// Fractional month-over-month change, or `nil` if no baseline.
    let monthDelta: Double?
    let currencyCode: String
    let locale: Locale

    var body: some View {
        AssetsBreakdownRow(
            leading: {
                MemberAvatarView(
                    name: memberName,
                    avatarData: avatarData,
                    seed: memberId,
                    size: 28
                )
            },
            title: memberName,
            caption: accountCount.map { String(localized: "assets.member.accountCount \($0)") },
            trailing: {
                AssetsBreakdownAmount(amount: amount, currencyCode: currencyCode, locale: locale)
            },
            share: share,
            monthDelta: monthDelta,
            currencyCode: currencyCode,
            locale: locale
        )
    }
}

// MARK: - Snapshot row

/// Single-line snapshot entry: month with optional note, total, chevron.
struct AssetsSnapshotRow: View {
    let snapshot: PortfolioSnapshot
    /// The chronologically-prior snapshot (older). Used for the VoiceOver delta.
    let previous: PortfolioSnapshot?
    /// User's current home currency — snapshots captured in another currency
    /// show their code tag.
    let homeCurrency: String
    let locale: Locale

    var body: some View {
        HStack(spacing: LedgerMetrics.columnSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: monthLabel)
                    .font(.callout)
                    .foregroundStyle(Color.ink)
                    .fixedSize()
                if let note = snapshot.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if snapshot.homeCurrency != homeCurrency {
                CurrencyCodeTag(code: snapshot.homeCurrency)
            }
            Text(
                snapshot.totalAmount,
                format: .currency(code: snapshot.homeCurrency)
                    .locale(locale)
                    .precision(.fractionLength(0))
            )
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .fixedSize()
            LedgerChevron()
        }
        .frame(minHeight: LedgerMetrics.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(deltaPercent.map { Text($0, format: .percent.precision(.fractionLength(1))) } ?? Text(verbatim: ""))
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

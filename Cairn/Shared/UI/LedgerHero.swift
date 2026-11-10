import SwiftUI

// Hero summary pieces for the 「私人银行」 layout (docs/design.md §5.2, §6):
// baseline-aligned amount, direction-arrow delta line, and number helpers.

// MARK: - Hero

/// Splits a currency amount into its symbol and digits so the symbol can be
/// set smaller on the same baseline, honoring the locale's symbol position.
struct CurrencyAmountParts {
    let sign: String
    let symbol: String
    let digits: String
    let symbolLeads: Bool

    init(_ amount: Decimal, code: String, locale: Locale, fractionDigits: Int = 0) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        let format = formatter.positiveFormat ?? "¤#"
        let symbolIndex = format.firstIndex(of: "¤")
        let digitIndex = format.firstIndex { $0 == "#" || $0 == "0" }
        symbolLeads = symbolIndex.map { index in digitIndex.map { index < $0 } ?? true } ?? true
        symbol = formatter.currencySymbol ?? code
        sign = amount < 0 ? "−" : ""
        let magnitude = amount < 0 ? -amount : amount
        digits = magnitude.formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(locale)
        )
    }
}

/// Hero amount: 46pt semibold digits with a 19pt currency symbol aligned to
/// the same baseline. Scales with Dynamic Type.
struct LedgerHeroAmount: View {
    let amount: Decimal
    let code: String
    let locale: Locale

    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 46
    @ScaledMetric(relativeTo: .title3) private var symbolSize: CGFloat = 19

    var body: some View {
        let parts = CurrencyAmountParts(amount, code: code, locale: locale)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if parts.symbolLeads {
                symbolText(parts.sign + parts.symbol)
                digitsText(parts.digits)
            } else {
                digitsText(parts.sign + parts.digits)
                symbolText(parts.symbol)
            }
        }
        .foregroundStyle(Color.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(amount, format: .currency(code: code).precision(.fractionLength(0)).locale(locale)))
    }

    private func symbolText(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.system(size: symbolSize, weight: .semibold))
    }

    private func digitsText(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.system(size: digitSize, weight: .semibold))
            .tracking(-digitSize * 0.025)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

/// Month-over-month line: `↗ US$3,300  0.3%  较上月`. Direction is carried by
/// the arrow; positive in `accent`, negative in `ink2`, flat without arrow.
struct LedgerDeltaLine: View {
    let amount: Decimal?
    let percent: Double?
    let code: String
    let locale: Locale
    var caption: Text?

    var body: some View {
        let direction = sign
        let tint: Color = direction > 0 ? .accent : .ink2
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if direction != 0 {
                    Image(systemName: direction > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                        .accessibilityLabel(Text(direction > 0 ? "common.delta.up" : "common.delta.down"))
                }
                if let amount {
                    Text(magnitude(amount), format: .currency(code: code).precision(.fractionLength(0)).locale(locale))
                }
            }
            if let percent {
                Text(abs(percent), format: .percent.precision(.fractionLength(1)))
            }
            if let caption {
                caption
                    .fontWeight(.regular)
                    .foregroundStyle(Color.ink2)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }

    private var sign: Int {
        if let amount { return amount > 0 ? 1 : (amount < 0 ? -1 : 0) }
        if let percent { return percent > 0 ? 1 : (percent < 0 ? -1 : 0) }
        return 0
    }

    private func magnitude(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
}

/// Hero summary block (§5.2): eyebrow + currency chip, amount, delta, meta.
/// No card ground; the following section's hairline separates it.
struct LedgerHero<Meta: View>: View {
    let eyebrow: Text
    let amount: Decimal
    let code: String
    let locale: Locale
    var deltaAmount: Decimal?
    var deltaPercent: Double?
    var showsDelta: Bool = true
    @ViewBuilder var meta: () -> Meta

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                eyebrow
                    .font(.subheadline)
                    .foregroundStyle(Color.ink2)
                Spacer(minLength: 8)
                CurrencyChip(code: code)
            }
            LedgerHeroAmount(amount: amount, code: code, locale: locale)
                .padding(.top, 10)
            if showsDelta, deltaAmount != nil || deltaPercent != nil {
                LedgerDeltaLine(
                    amount: deltaAmount,
                    percent: deltaPercent,
                    code: code,
                    locale: locale,
                    caption: Text("dashboard.vsLastMonth")
                )
                .padding(.top, 10)
            }
            meta()
                .font(.footnote)
                .foregroundStyle(Color.ink3)
                .padding(.top, 3)
        }
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ledger number formatting

/// Detail-figure formatting (§6): ledger values keep the currency's minor
/// units (two decimals for most), display-only.
enum LedgerAmountFormat {
    /// Fraction digits the currency uses (e.g. 2 for USD, 0 for JPY).
    static func minorUnits(for code: String, locale: Locale) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        return formatter.maximumFractionDigits
    }

    /// `+300.00` / `−300.00` / `0.00`, without a currency symbol.
    static func signed(_ value: Decimal, digits: Int, locale: Locale) -> String {
        let magnitude = value < 0 ? -value : value
        let body = magnitude.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        if value > 0 { return "+" + body }
        if value < 0 { return "−" + body }
        return body
    }
}

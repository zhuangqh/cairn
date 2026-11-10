import SwiftUI

// Shared building blocks for the 「私人银行」 layout (docs/design.md §4–§5):
// hairline-ruled sections with 20pt bold titles, 48pt rows on shared column
// widths, currency-code tags, progress rows, and two-segment composition bars.

// MARK: - Metrics

/// Shared column widths so related values line up across rows and sections.
enum LedgerMetrics {
    /// Leading mark column (avatar, currency tag, glyph tile).
    static let leadingColumn: CGFloat = 36
    /// Share-of-total column, trailing aligned.
    static let shareColumn: CGFloat = 44
    /// Gap between grid columns.
    static let columnSpacing: CGFloat = 12
    /// Minimum row height.
    static let rowHeight: CGFloat = 48
}

// MARK: - Hairline

/// 0.5pt `line` separator used between sections and rows.
struct LedgerHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.line)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

// MARK: - Section

/// Section with a top hairline, a 20pt bold title, and at most one trailing
/// action (link, filter, range picker, or meta text). The header reflows to
/// two lines rather than shrinking when the title and action don't fit.
struct LedgerSection<Accessory: View, Content: View>: View {
    let title: Text
    var showsRule: Bool = true
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        _ title: Text,
        showsRule: Bool = true,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsRule = showsRule
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    titleView
                    Spacer(minLength: 0)
                    accessory()
                }
                VStack(alignment: .leading, spacing: 6) {
                    titleView
                    accessory()
                }
            }
            .frame(minHeight: 30)

            content()
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsRule { LedgerHairline() }
        }
    }

    private var titleView: some View {
        title
            .font(.title3.bold())
            .tracking(-0.2)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

extension LedgerSection where Accessory == EmptyView {
    init(_ title: Text, showsRule: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, showsRule: showsRule, accessory: { EmptyView() }, content: content)
    }
}

/// Accent text action with a trailing chevron, e.g. 「全部 ›」.
struct LedgerSectionLink: View {
    let title: Text

    var body: some View {
        HStack(spacing: 4) {
            title
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.accent)
    }
}

/// Year-filter label for section headers: 「⚟ 2026」.
struct LedgerFilterLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(verbatim: title)
                .monospacedDigit()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.accent)
    }
}

/// 7pt-wide trailing chevron for navigation rows.
struct LedgerChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ink3)
            .accessibilityHidden(true)
    }
}

// MARK: - Tags and swatches

/// Currency code tag (36×22, hairline outline, SF Mono). Replaces flags.
/// Fixed size so it always fits the shared leading column; the full currency
/// name beside it carries the scalable text.
struct CurrencyCodeTag: View {
    let code: String
    private let width: CGFloat = 36
    private let height: CGFloat = 22

    var body: some View {
        Text(verbatim: code)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color.ink2)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// Outlined currency chip used in hero eyebrows (e.g. `USD`).
struct CurrencyChip: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .font(.caption.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.field.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
    }
}

/// 9pt category colour swatch.
struct LedgerSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }
}

/// Rounded glyph tile on `accentSoft` (account / category icons).
struct LedgerGlyphTile: View {
    let systemName: String
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(Color.accent)
            .frame(width: size, height: size)
            .background(Color.accentSoft, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Meter and composition bar

/// 3pt progress meter on the `track` rail.
struct LedgerMeter: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                Capsule()
                    .fill(Color.accent)
                    .frame(width: clamped > 0 ? max(3, geo.size.width * clamped) : 0)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Two-segment 8pt bar (accent / accent2) with a legend split across both
/// ends: name followed by a bold percentage.
struct CompositionBar: View {
    /// Share of the first segment, 0…1.
    let firstShare: Double
    let firstTitle: Text
    let secondTitle: Text

    var body: some View {
        let first = max(0, min(1, firstShare))
        let second = 1 - first
        VStack(spacing: 10) {
            GeometryReader { geo in
                let gap: CGFloat = (first > 0 && second > 0) ? 3 : 0
                let usable = max(0, geo.size.width - gap)
                HStack(spacing: gap) {
                    if first > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.accent)
                            .frame(width: usable * first)
                    }
                    if second > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.accent2)
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                legend(firstTitle, share: first)
                Spacer(minLength: 12)
                legend(secondTitle, share: second)
            }
            .font(.subheadline)
            .foregroundStyle(Color.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func legend(_ title: Text, share: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            title
            Text(share, format: .percent.precision(.fractionLength(0)))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

// MARK: - Rows

/// Progress row (§5.4): leading mark / name with inline caption / trailing
/// value / share, with a 3pt meter under the row starting at the name column.
struct LedgerProgressRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    let title: String
    var caption: String?
    @ViewBuilder let trailing: () -> Trailing
    /// 0…1 share; `nil` renders "—" and an empty meter.
    let share: Double?
    /// When false the share column and meter are omitted.
    var showsShare: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: LedgerMetrics.columnSpacing) {
                leading()
                    .frame(width: LedgerMetrics.leadingColumn, alignment: .leading)
                // Caption sits inline; when the line is too tight it drops
                // under the name instead of breaking inside a number.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        titleText.fixedSize()
                        captionText.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                        captionText
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                trailing()
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .fixedSize()
                if showsShare {
                    Text(verbatim: shareString)
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.ink3)
                        .frame(width: LedgerMetrics.shareColumn, alignment: .trailing)
                }
            }
            .frame(minHeight: 28)
            if showsShare {
                LedgerMeter(progress: share ?? 0)
                    .padding(.leading, LedgerMetrics.leadingColumn + LedgerMetrics.columnSpacing)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(verbatim: title)
            .font(.callout)
            .foregroundStyle(Color.ink)
            .lineLimit(2)
    }

    /// Multi-word captions (owner · dates) may wrap; a single token such as
    /// an amount stays whole rather than breaking mid-number.
    @ViewBuilder
    private var captionText: some View {
        if let caption {
            let text = Text(verbatim: caption)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.ink3)
            if caption.contains(where: \.isWhitespace) {
                text.lineLimit(2)
            } else {
                text.lineLimit(1).fixedSize()
            }
        }
    }

    private var shareString: String {
        guard let share else { return "—" }
        return share.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Vertical stack of rows separated by hairlines that start at `inset`
/// (the content column), matching §4's row rules.
struct LedgerRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    var inset: CGFloat = 0
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 {
                    LedgerHairline().padding(.leading, inset)
                }
                row(element)
            }
        }
    }
}

// MARK: - Range picker

/// Text-only segmented choice for section headers (§5.7): the selected
/// option gets an `accentSoft` ground and semibold weight.
struct LedgerTextPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> Text

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    title(option)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.ink : Color.ink2)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentSoft : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

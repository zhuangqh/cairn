import SwiftUI

// MARK: - Cairn palette
//
// 「私人银行」 palette (docs/design.md §2): warm ivory ground, ink-green
// accent, hairline separators. Light values follow the spec exactly. Dark
// mode has not been designed yet; the dark variants below are a provisional
// counterpart (warm near-black ground, lifted ink-green so the accent keeps
// its identity and contrast) pending a dedicated dark design (§9).

public extension Color {
    /// Page ground — warm ivory.
    static let pageBackground = Color(light: Color(hex: 0xF7F6F2), dark: Color(hex: 0x131614))
    /// Primary text, amounts, titles.
    static let ink = Color(light: Color(hex: 0x1E2A24), dark: Color(hex: 0xECEDE8))
    /// Secondary text, labels, unselected controls.
    static let ink2 = Color(light: Color(hex: 0x5F6862), dark: Color(hex: 0xA6ADA8))
    /// Tertiary captions, shares, axis labels, chevrons.
    static let ink3 = Color(light: Color(hex: 0x8D948F), dark: Color(hex: 0x7C847F))
    /// Hairline separators and outlines.
    static let line = Color(
        light: Color(hex: 0x1E2A24, opacity: 0.12),
        dark: Color(hex: 0xECEDE8, opacity: 0.12)
    )
    /// Ink-green accent: interactive elements, selection, positive change.
    static let accent = Color(light: Color(hex: 0x2D5A47), dark: Color(hex: 0x7FB59A))
    /// Pressed state for accent-filled buttons.
    static let accentActive = Color(light: Color(hex: 0x234737), dark: Color(hex: 0x6A9C83))
    /// Second segment of two-part composition bars.
    static let accent2 = Color(light: Color(hex: 0xC9D6CC), dark: Color(hex: 0x3B5146))
    /// Selected fills, icon tiles, selected tab capsule.
    static let accentSoft = Color(
        light: Color(hex: 0x2D5A47, opacity: 0.08),
        dark: Color(hex: 0x7FB59A, opacity: 0.14)
    )
    /// Empty track behind meters and share bars.
    static let track = Color(
        light: Color(hex: 0x1E2A24, opacity: 0.07),
        dark: Color(hex: 0xECEDE8, opacity: 0.08)
    )
    /// Input field fill.
    static let field = Color(light: .white, dark: Color(hex: 0x1C201D))
    /// Photo / thumbnail tile ground.
    static let thumb = Color(light: Color(hex: 0xEEEBE3), dark: Color(hex: 0x222723))
    /// Blank-input placeholder text (§5.12).
    static let placeholder = Color(light: Color(hex: 0xB7BBB6), dark: Color(hex: 0x5E6560))

    /// Quiet raised surface for the few remaining contained groups (forms,
    /// sheets). Data sections sit directly on `pageBackground` instead.
    static let notionSurface = Color(light: Color(hex: 0xFDFCF9), dark: Color(hex: 0x1A1E1B))
    /// Recessed surface — same as the page ground.
    static let notionSurfaceAlt = Color(light: Color(hex: 0xF0EEE8), dark: Color(hex: 0x0F1210))

    /// Legacy badge pair, now mapped onto the accent family.
    static let notionBadgeBlueBg = accentSoft
    static let notionBadgeBlueText = accent

    // Legacy semantic accents, desaturated into the ink-green family. Kept so
    // screens not yet restyled stay within the palette (§2 forbids candy hues).
    static let notionTeal = Color(light: Color(hex: 0x6F927F), dark: Color(hex: 0x8FB09E))
    static let notionGreen = accent
    static let notionOrange = ink2
    static let notionPink = Color(hex: 0xA9BEB0)
    static let notionPurple = Color(hex: 0x6B604B)
    static let notionBrown = Color(hex: 0x6B604B)

    /// Brass — second accent for achievements, milestones, and "now"
    /// markers. Never used for interaction or for gain/loss.
    static let brass = Color(light: Color(hex: 0xA8834A), dark: Color(hex: 0xCDAA6E))
    /// Tinted ground behind brass marks.
    static let brassSoft = Color(
        light: Color(hex: 0xA8834A, opacity: 0.14),
        dark: Color(hex: 0xCDAA6E, opacity: 0.16)
    )
    /// Muted terracotta and mist blue complete the category palette.
    static let terracotta = Color(light: Color(hex: 0xB4775A), dark: Color(hex: 0xD49A7E))
    static let mist = Color(light: Color(hex: 0x6F8796), dark: Color(hex: 0x9AB0BE))
    /// Brick red for market moves (see `ChangeTone`); ≥4.5:1 on `pageBackground`.
    /// Validation errors keep the system red.
    static let brick = Color(light: Color(hex: 0xB5523B), dark: Color(hex: 0xE08A72))

    /// Category palette: equal lightness and saturation, distinct hues.
    static let categoryPalette: [Color] = [accent, mist, brass, terracotta]
}

// MARK: - Gain / loss colour

/// Colour for a month-over-month move. Chinese readers expect red for a
/// rise and green for a fall (红涨绿跌); other locales get green up, red down.
/// Direction is always also carried by the ↗ / ↘ arrow.
enum ChangeTone {
    static func color(sign: Int, locale: Locale) -> Color {
        guard sign != 0 else { return .ink2 }
        let redMeansRise = locale.language.languageCode == .chinese
        return (sign > 0) == redMeansRise ? .brick : .accent
    }

    static func color(for value: Decimal, locale: Locale) -> Color {
        color(sign: value > 0 ? 1 : (value < 0 ? -1 : 0), locale: locale)
    }

    static func color(for value: Double, locale: Locale) -> Color {
        color(sign: value > 0 ? 1 : (value < 0 ? -1 : 0), locale: locale)
    }
}

// MARK: - Card modifier

/// Stable content surface. Liquid Glass is intentionally reserved for floating
/// navigation and controls; data cards stay visually quiet and readable.
/// The type name remains stable to avoid churning every feature call site.
public struct NotionCardStyle: ViewModifier {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var surface: Color

    public init(cornerRadius: CGFloat = 12, padding: CGFloat = 20, surface: Color = .notionSurface) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.surface = surface
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(surface, in: shape)
            .overlay(shape.strokeBorder(Color.line, lineWidth: 0.5))
    }
}

public extension View {
    /// Wraps content in Cairn's adaptive translucent surface.
    func glassCard(cornerRadius: CGFloat = 12, padding: CGFloat = 20) -> some View {
        modifier(NotionCardStyle(cornerRadius: cornerRadius, padding: padding))
    }

    /// Lower-contrast card variant for nested or secondary content.
    func notionCardAlt(cornerRadius: CGFloat = 12, padding: CGFloat = 20) -> some View {
        modifier(NotionCardStyle(cornerRadius: cornerRadius, padding: padding, surface: .notionSurfaceAlt))
    }

    /// Uses Apple's interactive Liquid Glass button on the newest systems and
    /// the native prominent style on systems supported by the deployment target.
    @ViewBuilder
    func cairnProminentButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Secondary control treatment for compact actions placed above content.
    @ViewBuilder
    func cairnGlassButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

// MARK: - Page background

/// Solid warm-ivory page ground. Data surfaces carry no gradient or glow;
/// hierarchy comes from type, whitespace, and hairlines (design.md §1).
public struct AppBackground: View {
    public init() {}

    public var body: some View {
        Color.pageBackground.ignoresSafeArea()
    }
}

public extension View {
    /// Places an `AppBackground` behind the view, filling safe-area edges.
    func ambientBackground() -> some View {
        background(AppBackground())
    }

    /// Hides the default list/form chrome and drops a warm-white background
    /// behind the content.
    func glassListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground())
    }

    /// Standard page horizontal padding: the 22pt leading guide every title,
    /// row, and hairline starts from on iPhone (design.md §4); roomier on macOS.
    func pageHorizontalPadding() -> some View {
        #if os(iOS)
        padding(.horizontal, 22)
        #else
        padding(.horizontal, 24)
        #endif
    }
}

// MARK: - Glyph badge

/// Tinted leading accessory used for row icons. In Notion style the fill is
/// very light (`tint` at 10% opacity) with the icon in the full tint.
public struct GlyphBadge: View {
    public let systemName: String
    public let tint: Color
    public let size: CGFloat
    public let isCircle: Bool

    public init(systemName: String, tint: Color, size: CGFloat = 34, isCircle: Bool = false) {
        self.systemName = systemName
        self.tint = tint
        self.size = size
        self.isCircle = isCircle
    }

    public var body: some View {
        ZStack {
            Group {
                if isCircle {
                    Circle().fill(tint.opacity(0.10))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.10))
                }
            }
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Pill badge

/// Notion-style pill: fully-rounded, tinted background, 12pt semibold label
/// with the signature `+0.125` letter spacing.
public struct NotionPillBadge: View {
    public let text: LocalizedStringKey
    public let textColor: Color
    public let background: Color

    public init(
        _ text: LocalizedStringKey,
        textColor: Color = .notionBadgeBlueText,
        background: Color = .notionBadgeBlueBg
    ) {
        self.text = text
        self.textColor = textColor
        self.background = background
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.125)
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

/// Pill badge initialized with a raw (non-localized) string. Useful for
/// currency codes / member initials where the source is data, not a catalog.
public struct NotionPillRaw: View {
    public let text: String
    public let textColor: Color
    public let background: Color

    public init(
        _ text: String,
        textColor: Color = .notionBadgeBlueText,
        background: Color = .notionBadgeBlueBg
    ) {
        self.text = text
        self.textColor = textColor
        self.background = background
    }

    public var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .semibold, design: .default).monospaced())
            .tracking(0.125)
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

// MARK: - Primary button style

/// `#0075de` bg, white text, 4pt radius — the only saturated CTA per §4.
public struct NotionPrimaryButtonStyle: ButtonStyle {
    public var size: Size

    public enum Size { case regular, large }

    public init(size: Size = .regular) { self.size = size }

    public func makeBody(configuration: Configuration) -> some View {
        let vPad: CGFloat = size == .large ? 10 : 8
        let hPad: CGFloat = size == .large ? 18 : 14
        let weight: Font.Weight = .semibold
        let fontSize: CGFloat = size == .large ? 15 : 14
        return configuration.label
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(Color.white)
            .padding(.vertical, vPad)
            .padding(.horizontal, hPad)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isPressed ? Color.accentActive : Color.accent)
            )
            .opacity(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Translucent warm-gray secondary button (§4 Secondary/Tertiary).
public struct NotionSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.ink)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.10 : 0.05))
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Section header

/// "Feature sub-section" header per §3: all-caps 12pt semibold label with a
/// tinted glyph to its left. Used above card groupings.
public struct NotionSectionHeader: View {
    public let titleKey: LocalizedStringKey
    public let systemImage: String?
    public let tint: Color

    public init(_ titleKey: LocalizedStringKey, systemImage: String? = nil, tint: Color = .ink2) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(titleKey)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.125)
                .foregroundStyle(Color.ink2)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Typography helpers

public extension Font {
    /// Display hero (64 / 700 / tight). For landing-style moments.
    static let notionDisplay = Font.system(size: 44, weight: .bold, design: .default)
    /// Sub-heading used in card titles (22 / 700).
    static let notionCardTitle = Font.system(size: 22, weight: .bold, design: .default)
    /// Body large (20 / 600).
    static let notionBodyLarge = Font.system(size: 18, weight: .semibold, design: .default)
    /// Caption (14 / 500).
    static let notionCaption = Font.system(size: 13, weight: .medium, design: .default)
}

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Builds a dynamic color that flips between `light` and `dark` variants.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }
}

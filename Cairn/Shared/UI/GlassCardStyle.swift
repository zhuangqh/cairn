import SwiftUI

// MARK: - Notion palette
//
// A warm-neutral, Notion-inspired palette that the rest of the app pulls from.
// See `DESIGN.md` for the provenance of each swatch. Values automatically flip
// to a warm-dark variant in dark mode so the design language still feels
// "paper, not glass".

public extension Color {
    /// Near-black primary text (`rgba(0,0,0,0.95)` in light mode).
    static let notionInk = Color(
        light: Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.95),
        dark: Color(.sRGB, red: 0.96, green: 0.95, blue: 0.94, opacity: 1.0)
    )

    /// Secondary warm gray for descriptions, subtitles.
    static let notionInkSecondary = Color(
        light: Color(hex: 0x615D59),
        dark: Color(hex: 0xA39E98)
    )

    /// Muted warm gray for captions, placeholders.
    static let notionInkMuted = Color(
        light: Color(hex: 0xA39E98),
        dark: Color(hex: 0x7A7570)
    )

    /// Card / page surface.
    static let notionSurface = Color(
        light: Color(hex: 0xFFFFFF),
        dark: Color(hex: 0x2A2927)
    )

    /// Warm white alt surface for section alternation + window chrome.
    static let notionSurfaceAlt = Color(
        light: Color(hex: 0xF6F5F4),
        dark: Color(hex: 0x1E1D1B)
    )

    /// Whisper border — the signature "1px solid rgba(0,0,0,0.1)".
    static let notionBorder = Color(
        light: Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.10),
        dark: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.10)
    )

    /// Notion Blue (`#0075de`) — the only saturated color in the core chrome.
    static let notionBlue = Color(hex: 0x0075DE)
    /// Pressed / active state for primary buttons.
    static let notionBlueActive = Color(hex: 0x005BAB)
    /// Tinted pill background for status badges.
    static let notionBadgeBlueBg = Color(hex: 0xF2F9FF)
    /// Pill text color for status badges.
    static let notionBadgeBlueText = Color(hex: 0x097FE8)

    // Semantic accents
    static let notionTeal = Color(hex: 0x2A9D99)
    static let notionGreen = Color(hex: 0x1AAE39)
    static let notionOrange = Color(hex: 0xDD5B00)
    static let notionPink = Color(hex: 0xFF64C8)
    static let notionPurple = Color(hex: 0x391C57)
    static let notionBrown = Color(hex: 0x523410)
}

// MARK: - Card modifier

/// Notion-style surface: pure white fill, whisper `1px` border, and a
/// 4-layer cumulative shadow stack that never exceeds 0.05 opacity on any
/// single layer. Produces depth that is *felt* rather than seen.
///
/// The modifier keeps the `.glassCard(...)` name for backwards compatibility
/// with existing callers even though the implementation is now paper-like.
public struct NotionCardStyle: ViewModifier {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var surface: Color

    public init(cornerRadius: CGFloat = 12, padding: CGFloat = 20, surface: Color = .notionSurface) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.surface = surface
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.notionBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 4-layer cumulative shadow stack (see DESIGN.md §6).
            .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 4)
            .shadow(color: .black.opacity(0.027), radius: 7.85, x: 0, y: 2)
            .shadow(color: .black.opacity(0.02), radius: 2.9, x: 0, y: 0.8)
            .shadow(color: .black.opacity(0.01), radius: 1.04, x: 0, y: 0.17)
    }
}

public extension View {
    /// Wraps the view in a Notion-style card. The historical name
    /// `.glassCard` is preserved so existing call sites keep working.
    func glassCard(cornerRadius: CGFloat = 12, padding: CGFloat = 20) -> some View {
        modifier(NotionCardStyle(cornerRadius: cornerRadius, padding: padding))
    }

    /// Notion card variant that uses the warm-white alt surface.
    func notionCardAlt(cornerRadius: CGFloat = 12, padding: CGFloat = 20) -> some View {
        modifier(NotionCardStyle(cornerRadius: cornerRadius, padding: padding, surface: .notionSurfaceAlt))
    }
}

// MARK: - Ambient background

/// Window background: plain warm white (`#f6f5f4`) in light mode, warm dark in
/// dark mode. No gradients — Notion's visual rhythm comes from alternating
/// flat surfaces, not diffuse color washes.
public struct AppBackground: View {
    public init() {}

    public var body: some View {
        Color.notionSurfaceAlt.ignoresSafeArea()
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
                    .fill(configuration.isPressed ? Color.notionBlueActive : Color.notionBlue)
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
            .foregroundStyle(Color.notionInk)
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

    public init(_ titleKey: LocalizedStringKey, systemImage: String? = nil, tint: Color = .notionInkSecondary) {
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
                .foregroundStyle(Color.notionInkSecondary)
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

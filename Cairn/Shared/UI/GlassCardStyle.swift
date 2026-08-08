import SwiftUI

// MARK: - Cairn palette
//
// A quiet alpine palette for the app's Liquid Glass visual system.  The old
// `notion…` names are retained because they are used throughout the feature
// views, but the values now form a cool, coherent family rather than a flat
// paper-card theme.

public extension Color {
    /// Near-black primary text (`rgba(0,0,0,0.95)` in light mode).
    static let notionInk = Color(
        light: Color(hex: 0x102B2A),
        dark: Color(hex: 0xF2FBF9)
    )

    /// Secondary warm gray for descriptions, subtitles.
    static let notionInkSecondary = Color(
        light: Color(hex: 0x526A68),
        dark: Color(hex: 0xA7BFBB)
    )

    /// Muted warm gray for captions, placeholders.
    static let notionInkMuted = Color(
        light: Color(hex: 0x7D9491),
        dark: Color(hex: 0x7F9995)
    )

    /// Card / page surface.
    static let notionSurface = Color(
        light: Color.white.opacity(0.72),
        dark: Color(hex: 0x172725).opacity(0.78)
    )

    /// Warm white alt surface for section alternation + window chrome.
    static let notionSurfaceAlt = Color(
        light: Color(hex: 0xEEF5F3),
        dark: Color(hex: 0x0B1716)
    )

    /// Whisper border — the signature "1px solid rgba(0,0,0,0.1)".
    static let notionBorder = Color(
        light: Color(.sRGB, red: 0.12, green: 0.28, blue: 0.26, opacity: 0.13),
        dark: Color(.sRGB, red: 0.80, green: 0.95, blue: 0.92, opacity: 0.13)
    )

    /// Alpine teal — the single saturated accent used by controls and charts.
    static let notionBlue = Color(hex: 0x0A8178)
    /// Pressed / active state for primary buttons.
    static let notionBlueActive = Color(hex: 0x075F59)
    /// Tinted pill background for status badges.
    static let notionBadgeBlueBg = Color(hex: 0xE7F5F2)
    /// Pill text color for status badges.
    static let notionBadgeBlueText = Color(hex: 0x08736B)

    // Semantic accents
    static let notionTeal = Color(hex: 0x4B9C91)
    static let notionGreen = Color(hex: 0x21865B)
    static let notionOrange = Color(hex: 0xC76936)
    static let notionPink = Color(hex: 0xFF64C8)
    static let notionPurple = Color(hex: 0x391C57)
    static let notionBrown = Color(hex: 0x523410)
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
            .overlay(shape.strokeBorder(Color.notionBorder.opacity(0.72), lineWidth: 0.7))
            .shadow(color: Color(hex: 0x0B3D38).opacity(0.055), radius: 10, x: 0, y: 4)
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

// MARK: - Ambient background

/// A low-contrast atmospheric field. It gives the translucent surfaces
/// something to refract while keeping charts and monetary values calm.
public struct AppBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(light: Color(hex: 0xF7FAF8), dark: Color(hex: 0x081311)),
                    Color.notionSurfaceAlt,
                    Color(light: Color(hex: 0xE8F1F0), dark: Color(hex: 0x102321))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.notionBlue.opacity(0.08))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: -170, y: -280)

            Circle()
                .fill(Color(hex: 0xD4A96A).opacity(0.05))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: 190, y: 360)
        }
        .ignoresSafeArea()
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

    /// Standard page horizontal padding. Tighter on iOS so cards have more
    /// breathing room on small screens; roomier on macOS.
    func pageHorizontalPadding() -> some View {
        #if os(iOS)
        padding(.horizontal, 18)
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

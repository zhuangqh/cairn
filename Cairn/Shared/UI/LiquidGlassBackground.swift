import SwiftUI

/// Translucent "liquid glass" surface used for floating / pinned chrome
/// (e.g. the snapshot filter bar). Prefers Apple's native `.glassEffect`
/// Liquid Glass API when available (iOS 26 / macOS 26+) and falls back
/// to a hand-tuned material + highlight stroke composition on older OSes.
public struct LiquidGlassBackground: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color?

    public init(cornerRadius: CGFloat = 14, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(tint),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.plusLighter)
                        .opacity(0.35)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
    }
}

public extension View {
    /// Wraps the view in a translucent Liquid-Glass-style surface.
    func liquidGlassBackground(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, tint: tint))
    }
}

import SwiftUI

/// A Liquid Glass–inspired segmented control.
///
/// Renders a pill-shaped capsule filled with translucent material (frosted
/// glass), and a rounded "bubble" that slides between options using
/// `matchedGeometryEffect`. Adopts the native `.glassEffect(...)` modifier on
/// platforms that ship Liquid Glass (macOS 26+ / iOS 26+); gracefully falls
/// back to `.ultraThinMaterial` on older OSes so the project keeps its
/// macOS 14 deployment target.
///
/// Use it in place of `Picker(style: .segmented)` when the control is a
/// top-level view switcher and you want the Liquid Glass feel.
struct GlassSegmentedControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> LocalizedStringKey
    let icon: (Option) -> String?

    @Namespace private var bubbleNamespace

    init(
        selection: Binding<Option>,
        options: [Option],
        title: @escaping (Option) -> LocalizedStringKey,
        icon: @escaping (Option) -> String? = { _ in nil }
    ) {
        self._selection = selection
        self.options = options
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                button(for: option)
            }
        }
        .padding(3)
        .background(containerBackground)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.14),
                            Color.primary.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .shadow(color: .black.opacity(0.03), radius: 1, y: 0.5)
        .animation(.spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0.1), value: selection)
    }

    @ViewBuilder
    private var containerBackground: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(Color.notionBlue.opacity(0.035)),
                    in: Capsule(style: .continuous)
                )
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .allowsHitTesting(false)
                )
        }
    }

    private func button(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            HStack(spacing: 6) {
                if let symbol = icon(option) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title(option))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? Color.notionBlue : Color.notionInkSecondary)
            .background {
                if isSelected {
                    selectedBubble
                        .matchedGeometryEffect(id: "bubble", in: bubbleNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(SegmentButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectedBubble: some View {
        // The selected pill uses an adaptive surface fill (white in light
        // mode, elevated control color in dark mode) plus a soft inner
        // highlight. We avoid `.plusLighter` here so dark mode doesn't
        // show a glaring white top-edge.
        Capsule(style: .continuous)
            .fill(Color(nsColorName: nil, colorSpaceAdjusted: .white).opacity(0.76))
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1.5)
            .shadow(color: .black.opacity(0.04), radius: 1, y: 0.5)
    }
}

/// A lightweight button style that adds subtle hover + press feedback on
/// segmented options without fighting with the selected bubble's
/// `matchedGeometryEffect`.
private struct SegmentButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isHovering && !configuration.isPressed {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .transition(.opacity)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// Convenience so we can fill with a color that adapts to the window's
// effective appearance (bubble stays visually "elevated" in both light and
// dark mode). Uses NSColor.controlBackgroundColor semantics.
private extension Color {
    init(nsColorName: String?, colorSpaceAdjusted: Color) {
        #if canImport(AppKit)
        self = Color(nsColor: .controlBackgroundColor)
        #else
        self = colorSpaceAdjusted
        #endif
    }
}

#if DEBUG
private struct GlassSegmentedControlPreview: View {
    enum Demo: String, CaseIterable, Hashable { case trend, possessions }
    @State private var selection: Demo = .trend
    var body: some View {
        GlassSegmentedControl(
            selection: $selection,
            options: Demo.allCases,
            title: { opt in
                switch opt {
                case .trend: return "Trend"
                case .possessions: return "Possessions"
                }
            },
            icon: { opt in
                switch opt {
                case .trend: return "chart.line.uptrend.xyaxis"
                case .possessions: return "house.and.flag"
                }
            }
        )
        .frame(width: 320)
        .padding()
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

#Preview("GlassSegmentedControl") {
    GlassSegmentedControlPreview()
}
#endif

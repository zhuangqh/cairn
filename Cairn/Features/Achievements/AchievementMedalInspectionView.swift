import SwiftUI

/// Overlay content for a Fitness-style inspection transition. One continuous
/// progress value controls travel, scale, rotation and the supporting chrome,
/// so the medal never pauses at its back face while another animation catches up.
struct AchievementMedalInspectionView: View {
    let presentation: AchievementPresentation
    let title: String
    let requirement: String
    let sourceFrame: CGRect
    let progress: Double
    let canClose: Bool
    let onClose: () -> Void

    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .overlay {
                    Color(hex: 0x03110F)
                        .opacity(0.84)
                }
                .modifier(AchievementInspectionReveal(progress: progress, start: 0, end: 0.44))
                .ignoresSafeArea()

            ambientGlow

            Button {
                guard canClose else { return }
                onClose()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .disabled(!canClose)
            .accessibilityLabel(Text("common.action.done", bundle: localization.bundle))

            VStack(spacing: 16) {
                Spacer(minLength: 0)

                GeometryReader { proxy in
                    ZStack {
                        AchievementBadgeView(
                            presentation,
                            size: 190,
                            rotationY: reduceMotion ? 0 : progress * 360
                        )
                        .modifier(
                            AchievementInspectionMotion(
                                progress: reduceMotion ? 1 : progress,
                                sourceFrame: sourceFrame,
                                targetFrame: proxy.frame(in: .global)
                            )
                        )
                        .opacity(reduceMotion ? progress : 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 266, height: 266)
                .allowsHitTesting(false)
                .accessibilityLabel(Text(verbatim: title))

                Spacer(minLength: 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.065))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                        }
                        .allowsHitTesting(false)

                    VStack(spacing: 10) {
                        VStack(spacing: 10) {
                            Text(verbatim: title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            Text(verbatim: requirement)
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.68))
                                .multilineTextAlignment(.center)

                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                Text(verbatim: AchievementFormatting.month(presentation.logicalMonth, locale: locale))
                                if let amount = AchievementFormatting.amount(presentation, locale: locale) {
                                    Text(verbatim: "·")
                                    Text(verbatim: amount).monospacedDigit()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.54))
                        }
                        .allowsHitTesting(false)

                        AchievementShareButton(presentation: presentation)
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .padding(.top, 4)
                            .allowsHitTesting(canClose)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                }
                .frame(maxWidth: 460)
                .modifier(AchievementInspectionReveal(progress: progress, start: 0.70, end: 0.92, distance: 10))
            }
            .padding(24)
            .frame(maxWidth: 680, maxHeight: 760)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
    }

    private var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x42E2D0).opacity(0.095))
                .frame(width: 340, height: 340)
                .blur(radius: 58)
            Circle()
                .stroke(Color.white.opacity(0.065), lineWidth: 1)
                .frame(width: 300, height: 300)
        }
        .modifier(AchievementInspectionReveal(progress: progress, start: 0.10, end: 0.58))
        .allowsHitTesting(false)
    }
}

/// One transform owns the complete source-to-centre movement. A small lift at
/// mid-flight keeps the path physical without separating translation from turn.
private struct AchievementInspectionMotion: @MainActor AnimatableModifier {
    var progress: Double
    let sourceFrame: CGRect
    let targetFrame: CGRect

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let amount = min(1, max(0, progress))
        let remaining = 1 - amount
        let sourceScale = sourceFrame.width / max(targetFrame.width, 1)
        let scale = sourceScale + (1 - sourceScale) * amount
        let lift = sin(amount * .pi) * 18

        content
            .scaleEffect(scale)
            .offset(
                x: (sourceFrame.midX - targetFrame.midX) * remaining,
                y: (sourceFrame.midY - targetFrame.midY) * remaining - lift
            )
    }
}

/// Thresholded reveal driven by the same progress as the medal. Unlike a plain
/// opacity animation, this keeps copy and controls quiet until the turn settles.
private struct AchievementInspectionReveal: @MainActor AnimatableModifier {
    var progress: Double
    let start: Double
    let end: Double
    var distance: CGFloat = 0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let span = max(end - start, 0.001)
        let reveal = min(1, max(0, (progress - start) / span))
        content
            .opacity(reveal)
            .offset(y: distance * (1 - reveal))
    }
}

struct AchievementInspectionSourceFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func achievementInspectionSource(id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AchievementInspectionSourceFramesKey.self,
                    value: [id: proxy.frame(in: .global)]
                )
            }
        }
    }
}

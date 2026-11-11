import SwiftUI

/// A medal and its original record, presented on the same quiet ledger ground
/// as the journal. The medal flies above the scrollable copy, so the scroll
/// view never clips it, and drops into its slot once settled.
struct AchievementMedalInspectionView: View {
    let presentation: AchievementPresentation
    var badgeStageKey: String?
    let title: String
    let requirement: String
    let sourceFrame: CGRect
    let progress: Double
    let canClose: Bool
    let onClose: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LocalizationService.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 32
    @State private var medalFrame: CGRect = .zero

    var body: some View {
        ZStack {
            AppBackground()
                .modifier(AchievementInspectionReveal(progress: progress, start: 0, end: 0.44))

            VStack(spacing: 0) {
                HStack {
                    Text("achievement.inspect.eyebrow", bundle: localization.bundle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.brass)
                    Spacer(minLength: 12)
                    InspectionCloseButton(canClose: canClose, action: onClose)
                }
                .inspectionColumn()
                .modifier(AchievementInspectionReveal(progress: progress, start: 0.62, end: 0.92))

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        medal
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)

                        Text(verbatim: title)
                            .font(.system(size: titleSize, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 24)
                            .modifier(copyReveal)

                        record
                            .modifier(copyReveal)

                        VStack(spacing: 12) {
                            AchievementShareButton(presentation: presentation, fillsWidth: true)
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                .controlSize(.large)
                                .tint(Color.accent)
                                .foregroundStyle(colorScheme == .dark ? Color.pageBackground : .white)
                                .allowsHitTesting(canClose)
                            Text("achievement.inspect.privacy", bundle: localization.bundle)
                                .font(.caption)
                                .foregroundStyle(Color.ink2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                        .modifier(copyReveal)
                    }
                    .inspectionColumn()
                }
                .scrollIndicators(.hidden)
            }

            InspectionFlightLayer(
                sourceFrame: sourceFrame,
                targetFrame: medalFrame,
                progress: progress,
                isSettled: canClose
            ) { _ in
                badge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A tap anywhere outside a control closes, so the small close glyph
        // is not the only way back. The host ignores taps mid-flight.
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityAddTraits(.isModal)
    }

    private var medal: some View {
        InspectionFlightSlot(isSettled: canClose, targetFrame: $medalFrame) { _ in
            badge
        }
        .frame(width: 252, height: 252)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var badge: some View {
        AchievementBadgeView(
            family: presentation.family,
            stageKey: badgeStageKey ?? presentation.stageKey,
            size: 180,
            rotationY: reduceMotion ? 0 : progress * 360
        )
    }

    private var record: some View {
        LedgerSection(Text("achievement.inspect.record", bundle: localization.bundle)) {
            VStack(spacing: 0) {
                detailRow("achievement.inspect.requirement", value: requirement)
                LedgerHairline()
                detailRow(
                    "achievement.inspect.month",
                    value: AchievementFormatting.month(presentation.logicalMonth, locale: locale)
                )
                if let value = recordedValue {
                    LedgerHairline()
                    detailRow("achievement.inspect.value", value: value)
                }
            }
        }
    }

    private func detailRow(_ label: LocalizedStringKey, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(label, bundle: localization.bundle).foregroundStyle(Color.ink2).fixedSize()
                Spacer(minLength: 0)
                Text(verbatim: value).foregroundStyle(Color.ink).fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(label, bundle: localization.bundle).foregroundStyle(Color.ink2)
                Text(verbatim: value).foregroundStyle(Color.ink)
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var recordedValue: String? {
        if presentation.family == .timeMark, let amount = presentation.observedAmount {
            return String(
                format: String(localized: "achievement.timeMark.description", bundle: localization.bundle),
                NSDecimalNumber(decimal: amount).intValue
            )
        }
        return AchievementFormatting.amount(presentation, locale: locale)
    }

    private var copyReveal: AchievementInspectionReveal {
        AchievementInspectionReveal(progress: progress, start: 0.62, end: 0.92)
    }
}

extension View {
    /// Shows an inspection overlay above this view. On iOS it is a clear
    /// full-screen cover, so it covers the navigation and tab bars instead of
    /// hiding them; hiding them shrinks the safe area and shifts the page
    /// underneath. Present and dismiss inside a transaction with
    /// `disablesAnimations` so the cover skips the system slide; the overlay
    /// animates itself, starting from `onPresented` once it is on screen.
    /// `onDismissed` runs once the overlay is fully gone, the earliest point
    /// another sheet can be presented.
    @ViewBuilder
    func inspectionPresentation<Overlay: View>(
        isPresented: Bool,
        onPresented: @escaping () -> Void,
        onDismissed: (() -> Void)? = nil,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: .init(get: { isPresented }, set: { _ in }), onDismiss: onDismissed) {
            overlay()
                .presentationBackground(.clear)
                .onAppear(perform: onPresented)
        }
        #else
        self.overlay {
            if isPresented {
                overlay()
                    .onAppear(perform: onPresented)
                    .onDisappear { onDismissed?() }
            }
        }
        #endif
    }

    /// The overlays' shared content column: page margins and a 640pt cap,
    /// centred. Applied to the header and to the scroll content rather than
    /// around the scroll view, so the scroll view spans the window and its
    /// bar sits at the window edge instead of beside the content.
    func inspectionColumn() -> some View {
        pageHorizontalPadding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
    }
}

/// Close control for the inspection overlays. The 44pt hit area sits inside
/// the trailing page guide, and the glyph's ink, not its symbol box, ends on
/// that guide, flush with the content edges below it.
struct InspectionCloseButton: View {
    let canClose: Bool
    let action: () -> Void

    @Environment(LocalizationService.self) private var localization
    /// Side bearing of `xmark` at body size, measured from the rendered glyph.
    @ScaledMetric(relativeTo: .body) private var opticalInset: CGFloat = 2.3

    var body: some View {
        let inset = opticalInset
        Button(action: action) {
            Label {
                Text("common.action.done", bundle: localization.bundle)
            } icon: {
                Image(systemName: "xmark")
                    .alignmentGuide(.trailing) { $0[.trailing] - inset }
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .frame(width: 44, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accent)
        // Not `.disabled`: that restyles the control mid-flight.
        .allowsHitTesting(canClose)
        .keyboardShortcut(.cancelAction)
    }
}

/// The slot a flying figure lands in, inside the overlay's scroll view. It
/// reports its frame for `InspectionFlightLayer` and only draws the figure
/// once the flight has settled, so the figure then scrolls with the copy.
struct InspectionFlightSlot<Figure: View>: View {
    let isSettled: Bool
    @Binding var targetFrame: CGRect
    @ViewBuilder let figure: (CGSize) -> Figure

    var body: some View {
        GeometryReader { proxy in
            if isSettled {
                figure(proxy.size)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { targetFrame = $0 }
    }
}

/// Carries a figure between its source and its slot above the overlay's
/// scroll view, which would otherwise clip it at the page margins and under
/// the header row. Hands the figure to the slot once settled.
struct InspectionFlightLayer<Figure: View>: View {
    let sourceFrame: CGRect
    let targetFrame: CGRect
    let progress: Double
    let isSettled: Bool
    @ViewBuilder let figure: (CGSize) -> Figure

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if !isSettled, !targetFrame.isEmpty {
                let origin = proxy.frame(in: .global).origin
                figure(targetFrame.size)
                    .frame(width: targetFrame.width, height: targetFrame.height)
                    .modifier(
                        AchievementInspectionMotion(
                            progress: reduceMotion ? 1 : progress,
                            sourceFrame: sourceFrame,
                            targetFrame: targetFrame
                        )
                    )
                    .opacity(reduceMotion ? progress : 1)
                    .position(x: targetFrame.midX - origin.x, y: targetFrame.midY - origin.y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One transform owns the complete source-to-centre movement. A small lift at
/// mid-flight keeps the path physical without separating translation from turn.
struct AchievementInspectionMotion: @MainActor AnimatableModifier {
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
struct AchievementInspectionReveal: @MainActor AnimatableModifier {
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

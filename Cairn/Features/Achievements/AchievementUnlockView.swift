import SwiftUI
#if os(iOS)
import UIKit
#endif

struct AchievementUnlockView: View {
    let events: [AchievementPresentation]
    let onComplete: () -> Void

    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var phase: RevealPhase = .hidden

    private var current: AchievementPresentation { events[index] }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x071714), Color(hex: 0x102622), Color(hex: 0x0A1D1A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Color.black
                .opacity(phase.backgroundDim)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                Spacer(minLength: 20)

                AchievementBadgeView(
                    current,
                    size: 150,
                    rotationY: reduceMotion ? 0 : phase.rotationY,
                    crackIntensity: phase.crackIntensity,
                    revealProgress: phase.surfaceReveal,
                    edgeHighlight: phase.edgeHighlight
                )
                .scaleEffect(phase.medalScale)
                .opacity(phase.medalOpacity)
                .background { ambientHalo }
                .overlay {
                    if !reduceMotion {
                        restrainedParticles
                            .frame(width: 360, height: 360)
                    }
                }

                VStack(spacing: 9) {
                    Text("achievement.unlock.eyebrow", bundle: localization.bundle)
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(hex: 0x8DE9DE))

                    Text(LocalizedStringKey(current.titleKey), bundle: localization.bundle)
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("achievement.unlock.headline", bundle: localization.bundle)
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.86))

                    description(current)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                }
                .opacity(phase.detailsOpacity)
                .offset(y: phase.detailsOpacity == 1 ? 0 : 10)

                HStack(spacing: 10) {
                    AchievementShareButton(presentation: current)
                        .buttonStyle(.bordered)
                        .tint(.white)

                    Button {
                        advance()
                    } label: {
                        Text(LocalizedStringKey(
                            index == events.count - 1
                                ? "common.action.done"
                                : "achievement.unlock.next"
                        ))
                        .frame(minWidth: 84)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.notionBlue)
                }
                .controlSize(.large)
                .opacity(phase.detailsOpacity)
                .offset(y: phase.detailsOpacity == 1 ? 0 : 8)
                .allowsHitTesting(phase == .settled)

                Group {
                    if events.count > 1 {
                        Text(verbatim: "\(index + 1) / \(events.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .opacity(phase.detailsOpacity)

                Spacer(minLength: 20)
            }
            .padding(28)
        }
        .task(id: index) {
            await runRevealTimeline()
        }
        .allowsHitTesting(phase == .settled)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var ambientHalo: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x42E2D0).opacity(0.08 * phase.crackIntensity))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .scaleEffect(0.72 + 0.28 * phase.medalScale)

            Circle()
                .stroke(Color.white.opacity(0.08 * phase.edgeHighlight), lineWidth: 1)
                .frame(width: 250, height: 250)
        }
        .allowsHitTesting(false)
    }

    private var restrainedParticles: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<10, id: \.self) { item in
                    let angle = Double(item) * 2.399963 + Double(pseudoRandom(item, salt: 17)) * 0.4
                    let distance = min(proxy.size.width, proxy.size.height)
                        * (0.16 + pseudoRandom(item, salt: 43) * 0.24)
                    Circle()
                        .fill(Color(hex: 0x53E1D0))
                        .frame(width: item.isMultiple(of: 4) ? 4 : 2.5)
                        .position(
                            x: proxy.size.width / 2 + CGFloat(cos(angle)) * distance * phase.particleProgress,
                            y: proxy.size.height / 2 + CGFloat(sin(angle)) * distance * phase.particleProgress
                        )
                        .scaleEffect(1 - phase.particleProgress * 0.42)
                        .opacity(phase.particleOpacity * (0.62 + Double(pseudoRandom(item, salt: 71)) * 0.30))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func pseudoRandom(_ value: Int, salt: Int) -> CGFloat {
        let mixed = abs((value + 1) * 1103515245 &+ salt * 12345)
        return CGFloat(mixed % 1000) / 1000
    }

    /// A single task advances the four explicit phases at 220, 650, 1250,
    /// and 1800 milliseconds. Cancellation is automatic when the event changes.
    @MainActor
    private func runRevealTimeline() async {
        phase = .hidden

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) {
                phase = .settling
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            phase = .settled
            playSettleHaptic()
            return
        }

        withAnimation(.easeOut(duration: 0.22)) {
            phase = .emerging
        }
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }

        playCrackHaptic()
        withAnimation(.easeOut(duration: 0.43)) {
            phase = .awakening
        }
        try? await Task.sleep(for: .milliseconds(430))
        guard !Task.isCancelled else { return }

        withAnimation(.timingCurve(0.20, 0.72, 0.25, 1, duration: 0.60)) {
            phase = .turning
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            phase = .settling
        }
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled else { return }

        phase = .settled
        playSettleHaptic()
    }

    private func playCrackHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.42)
        #endif
    }

    private func playSettleHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.48)
        #endif
    }

    private func advance() {
        guard phase == .settled else { return }
        if index < events.count - 1 {
            index += 1
        } else {
            onComplete()
        }
    }

    @ViewBuilder
    private func description(_ presentation: AchievementPresentation) -> some View {
        let month = AchievementFormatting.month(presentation.logicalMonth, locale: locale)
        if let amount = AchievementFormatting.amount(presentation, locale: locale), presentation.family != .timeMark {
            Text(verbatim: "\(amount) · \(month)")
        } else if presentation.family == .timeMark {
            let months = NSDecimalNumber(decimal: presentation.observedAmount ?? 0).intValue
            Text(String(format: String(localized: "achievement.timeMark.description", bundle: localization.bundle), months) + " · " + month)
        } else {
            Text(verbatim: month)
        }
    }
}

private enum RevealPhase: Equatable {
    case hidden
    case emerging
    case awakening
    case turning
    case settling
    case settled

    var medalScale: CGFloat {
        switch self {
        case .hidden: 0.62
        case .emerging: 0.78
        case .awakening: 0.86
        case .turning: 1.025
        case .settling, .settled: 1
        }
    }

    var medalOpacity: Double {
        switch self {
        case .hidden: 0.08
        case .emerging: 0.42
        case .awakening: 0.76
        case .turning, .settling, .settled: 1
        }
    }

    var backgroundDim: Double {
        switch self {
        case .hidden: 0
        case .emerging: 0.10
        case .awakening: 0.16
        case .turning, .settling, .settled: 0.22
        }
    }

    var crackIntensity: Double {
        switch self {
        case .hidden, .emerging: 0
        case .awakening, .turning, .settling, .settled: 1
        }
    }

    var surfaceReveal: Double {
        switch self {
        case .hidden, .emerging: 0.12
        case .awakening: 0.30
        case .turning, .settling, .settled: 1
        }
    }

    var edgeHighlight: Double {
        switch self {
        case .hidden, .emerging, .awakening: 0
        case .turning, .settling, .settled: 1
        }
    }

    var rotationY: Double {
        switch self {
        case .hidden, .emerging, .awakening: 0
        case .turning: 372
        case .settling, .settled: 360
        }
    }

    var particleProgress: CGFloat {
        switch self {
        case .hidden, .emerging: 0
        case .awakening: 0.86
        case .turning, .settling, .settled: 1
        }
    }

    var particleOpacity: Double {
        switch self {
        case .awakening: 0.82
        case .turning, .settling: 0
        default: 0
        }
    }

    var detailsOpacity: Double {
        switch self {
        case .settling, .settled: 1
        default: 0
        }
    }
}

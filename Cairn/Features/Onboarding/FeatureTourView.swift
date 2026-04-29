import SwiftUI

/// Unified welcome experience: a swipeable tour of Cairn's highlights that
/// optionally rolls into the first-run setup step (home currency) at the
/// end.
///
/// Two presentation modes:
///   • `.firstRun` — new-user flow. Highlights → home currency. Finishing
///     flips both `featureTourSeen` and `onboardingCompleted` and persists
///     the picked currency.
///   • `.replay` — re-shown from Settings. Just the highlights, ending in a
///     simple "Done" button.
struct FeatureTourView: View {
    enum Mode { case firstRun, replay }

    let mode: Mode

    init(mode: Mode = .replay) {
        self.mode = mode
    }

    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.featureTourSeen)
    private var featureTourSeen: Bool = false

    @AppStorage(AppSettingsKeys.onboardingCompleted)
    private var onboardingCompleted: Bool = false

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @State private var index: Int = 0
    @State private var dragOffset: CGFloat = 0

    private var pages: [Page] {
        switch mode {
        case .replay:    return Page.highlights
        case .firstRun:  return Page.highlights + [.homeCurrency]
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                topBar

                GeometryReader { proxy in
                    let width = proxy.size.width
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                            pageContent(page)
                                .frame(width: width)
                        }
                    }
                    .offset(x: -CGFloat(index) * width + dragOffset)
                    .frame(width: width, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Rubber-band at the edges so dragging past
                                // the first / last page doesn't tear the
                                // carousel off-screen.
                                let raw = value.translation.width
                                if (index == 0 && raw > 0) || (index == pages.count - 1 && raw < 0) {
                                    dragOffset = raw / 3
                                } else {
                                    dragOffset = raw
                                }
                            }
                            .onEnded { value in
                                let threshold = width * 0.25
                                let translation = value.translation.width
                                let predicted = value.predictedEndTranslation.width
                                withAnimation(.interpolatingSpring(stiffness: 240, damping: 28)) {
                                    if (translation < -threshold || predicted < -width * 0.5) && index < pages.count - 1 {
                                        index += 1
                                    } else if (translation > threshold || predicted > width * 0.5) && index > 0 {
                                        index -= 1
                                    }
                                    dragOffset = 0
                                }
                            }
                    )
                }

                pageIndicator
                    .padding(.top, 8)

                bottomBar
                    .padding(.top, 20)
                    .pageHorizontalPadding()
                    .padding(.bottom, 28)
            }
        }
        .keyboardDismissable()
        .interactiveDismissDisabled(mode == .firstRun)
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 580, idealHeight: 640)
        #endif
    }

    // MARK: - Page resolver

    @ViewBuilder
    private func pageContent(_ page: Page) -> some View {
        switch page {
        case .highlight(let highlight):
            HighlightPageView(highlight: highlight)
        case .homeCurrency:
            HomeCurrencyPageView(homeCurrency: $homeCurrency)
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: finish) {
                Text("tour.skip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.notionInkSecondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .opacity(canSkip ? 1 : 0)
            .accessibilityHidden(!canSkip)
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages.count, id: \.self) { idx in
                Capsule()
                    .fill(idx == index ? indicatorTint(for: pages[index]) : Color.notionInkMuted.opacity(0.35))
                    .frame(width: idx == index ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
            }
        }
    }

    private var bottomBar: some View {
        Button {
            if isLastPage { finish() } else { advance() }
        } label: {
            HStack(spacing: 8) {
                Text(primaryButtonLabel)
                if !isLastPage {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(NotionPrimaryButtonStyle(size: .large))
    }

    // MARK: - State

    private var isLastPage: Bool { index == pages.count - 1 }

    /// Skip is hidden on the very last page (the primary CTA itself acts
    /// as "finish").
    private var canSkip: Bool { !isLastPage }

    private var primaryButtonLabel: LocalizedStringKey {
        if !isLastPage { return "tour.next" }
        switch mode {
        case .firstRun: return "tour.finish"
        case .replay:   return "common.action.done"
        }
    }

    private func indicatorTint(for page: Page) -> Color {
        if case .highlight(let highlight) = page { return highlight.tint }
        return .notionBlue
    }

    // MARK: - Actions

    private func advance() {
        guard index < pages.count - 1 else { return }
        withAnimation(.interpolatingSpring(stiffness: 240, damping: 28)) { index += 1 }
    }

    private func finish() {
        featureTourSeen = true
        if mode == .firstRun {
            onboardingCompleted = true
        }
        dismiss()
    }
}

// MARK: - Page model

private extension FeatureTourView {
    enum Page {
        case highlight(Highlight)
        case homeCurrency

        static let highlights: [Page] = Highlight.all.map(Page.highlight)
    }

    struct Highlight {
        let symbol: String
        let tint: Color
        let titleKey: LocalizedStringKey
        let bodyKey: LocalizedStringKey
        let bullets: [LocalizedStringKey]

        static let all: [Highlight] = [
            Highlight(
                symbol: "mountain.2.fill",
                tint: .notionBlue,
                titleKey: "tour.page.welcome.title",
                bodyKey: "tour.page.welcome.body",
                bullets: [
                    "tour.page.welcome.bullet1",
                    "tour.page.welcome.bullet2",
                    "tour.page.welcome.bullet3"
                ]
            ),
            Highlight(
                symbol: "person.3.fill",
                tint: .notionPurple,
                titleKey: "tour.page.family.title",
                bodyKey: "tour.page.family.body",
                bullets: [
                    "tour.page.family.bullet1",
                    "tour.page.family.bullet2",
                    "tour.page.family.bullet3"
                ]
            ),
            Highlight(
                symbol: "dollarsign.arrow.circlepath",
                tint: .notionGreen,
                titleKey: "tour.page.currency.title",
                bodyKey: "tour.page.currency.body",
                bullets: [
                    "tour.page.currency.bullet1",
                    "tour.page.currency.bullet2",
                    "tour.page.currency.bullet3"
                ]
            ),
            Highlight(
                symbol: "chart.line.uptrend.xyaxis",
                tint: .notionPink,
                titleKey: "tour.page.trend.title",
                bodyKey: "tour.page.trend.body",
                bullets: [
                    "tour.page.trend.bullet1",
                    "tour.page.trend.bullet2",
                    "tour.page.trend.bullet3"
                ]
            ),
            Highlight(
                symbol: "lock.shield.fill",
                tint: .notionTeal,
                titleKey: "tour.page.privacy.title",
                bodyKey: "tour.page.privacy.body",
                bullets: [
                    "tour.page.privacy.bullet1",
                    "tour.page.privacy.bullet2",
                    "tour.page.privacy.bullet4",
                    "tour.page.privacy.bullet3"
                ]
            )
        ]
    }
}

// MARK: - Hero icon

private struct HeroIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.85), tint.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 116, height: 116)
                .shadow(color: tint.opacity(0.35), radius: 24, x: 0, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Highlight page

private struct HighlightPageView: View {
    let highlight: FeatureTourView.Highlight

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            HeroIcon(symbol: highlight.symbol, tint: highlight.tint)
            VStack(spacing: 12) {
                Text(highlight.titleKey)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.notionInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(highlight.bodyKey)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.notionInkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(highlight.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(highlight.tint)
                            .padding(.top, 2)
                        Text(bullet)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.notionInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14, padding: 18)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 480)
        .pageHorizontalPadding()
    }
}

// MARK: - Setup pages (first-run only)

private struct HomeCurrencyPageView: View {
    @Binding var homeCurrency: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            HeroIcon(symbol: "dollarsign.circle.fill", tint: .notionGreen)
            VStack(spacing: 12) {
                Text("onboarding.homeCurrency.title")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.notionInk)
                    .multilineTextAlignment(.center)
                Text("onboarding.homeCurrency.body")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.notionInkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("settings.homeCurrency.title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.notionInk)
                Spacer()
                Picker("", selection: $homeCurrency) {
                    Section("currency.picker.pinned") {
                        ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                            currencyLabel(code).tag(code)
                        }
                    }
                    Section("currency.picker.other") {
                        ForEach(CurrencyCatalog.rest, id: \.self) { code in
                            currencyLabel(code).tag(code)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .glassCard(cornerRadius: 14, padding: 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 480)
        .pageHorizontalPadding()
    }

    @ViewBuilder
    private func currencyLabel(_ code: String) -> some View {
        HStack {
            Text(verbatim: code).font(.body.monospaced())
            Text(verbatim: CurrencyCatalog.displayName(code))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Tour · replay") {
    FeatureTourView(mode: .replay)
        .modelContainer(PreviewSampleData.emptyContainer())
}

#Preview("Tour · first run") {
    UserDefaults.standard.set(false, forKey: AppSettingsKeys.onboardingCompleted)
    UserDefaults.standard.set(false, forKey: AppSettingsKeys.featureTourSeen)
    return FeatureTourView(mode: .firstRun)
        .modelContainer(PreviewSampleData.emptyContainer())
}
#endif

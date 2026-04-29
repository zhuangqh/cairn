import SwiftUI

/// A modern, swipeable highlights tour that introduces Cairn's key value
/// propositions to new users — and can be re-opened from Settings any time.
///
/// The view is purely presentational: it never touches the SwiftData store.
/// Finishing or skipping flips `featureTourSeen` so the first-run flow knows
/// not to show it again, and dismisses the surrounding sheet.
struct FeatureTourView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.featureTourSeen)
    private var featureTourSeen: Bool = false

    @State private var index: Int = 0

    private let pages: [TourPage] = TourPage.all

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                topBar

                GeometryReader { _ in
                    ZStack {
                        ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                            if offset == index {
                                TourPageView(page: page)
                                    .transition(pageTransition)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                #if os(iOS)
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            if value.translation.width < -40 { advance() }
                            else if value.translation.width > 40 { rewind() }
                        }
                )
                #endif

                pageIndicator
                    .padding(.top, 8)

                bottomBar
                    .padding(.top, 20)
                    .pageHorizontalPadding()
                    .padding(.bottom, 28)
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 620)
        #endif
        .interactiveDismissDisabled(false)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                finish()
            } label: {
                Text("tour.skip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.notionInkSecondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .opacity(isLastPage ? 0 : 1)
            .accessibilityHidden(isLastPage)
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? pages[index].tint : Color.notionInkMuted.opacity(0.35))
                    .frame(width: i == index ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                rewind()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.notionInk)
                    .background(
                        Circle().fill(Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .opacity(index == 0 ? 0.35 : 1)
            .disabled(index == 0)
            .accessibilityLabel(Text("tour.back"))

            Spacer(minLength: 8)

            Button {
                if isLastPage { finish() } else { advance() }
            } label: {
                HStack(spacing: 8) {
                    Text(isLastPage ? "tour.finish" : "tour.next")
                    if !isLastPage {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(NotionPrimaryButtonStyle(size: .large))
        }
    }

    // MARK: - Helpers

    private var isLastPage: Bool { index == pages.count - 1 }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advance() {
        guard index < pages.count - 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            index += 1
        }
    }

    private func rewind() {
        guard index > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            index -= 1
        }
    }

    private func finish() {
        featureTourSeen = true
        dismiss()
    }
}

// MARK: - Page model

private struct TourPage: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
    let bullets: [LocalizedStringKey]

    static let all: [TourPage] = [
        TourPage(
            symbol: "person.3.fill",
            tint: .notionBlue,
            titleKey: "tour.page.family.title",
            bodyKey: "tour.page.family.body",
            bullets: [
                "tour.page.family.bullet1",
                "tour.page.family.bullet2",
                "tour.page.family.bullet3"
            ]
        ),
        TourPage(
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
        TourPage(
            symbol: "tablecells.badge.ellipsis",
            tint: .notionOrange,
            titleKey: "tour.page.batch.title",
            bodyKey: "tour.page.batch.body",
            bullets: [
                "tour.page.batch.bullet1",
                "tour.page.batch.bullet2",
                "tour.page.batch.bullet3"
            ]
        ),
        TourPage(
            symbol: "chart.line.uptrend.xyaxis",
            tint: .notionPurple,
            titleKey: "tour.page.trend.title",
            bodyKey: "tour.page.trend.body",
            bullets: [
                "tour.page.trend.bullet1",
                "tour.page.trend.bullet2",
                "tour.page.trend.bullet3"
            ]
        ),
        TourPage(
            symbol: "lock.shield.fill",
            tint: .notionTeal,
            titleKey: "tour.page.privacy.title",
            bodyKey: "tour.page.privacy.body",
            bullets: [
                "tour.page.privacy.bullet1",
                "tour.page.privacy.bullet2",
                "tour.page.privacy.bullet3"
            ]
        )
    ]
}

// MARK: - Single page

private struct TourPageView: View {
    let page: TourPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            heroIcon
            VStack(spacing: 12) {
                Text(page.titleKey)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.notionInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.bodyKey)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.notionInkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(page.tint)
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

    private var heroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [page.tint.opacity(0.85), page.tint.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 116, height: 116)
                .shadow(color: page.tint.opacity(0.35), radius: 24, x: 0, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )

            Image(systemName: page.symbol)
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

#if DEBUG
#Preview("Feature tour") {
    FeatureTourView()
}
#endif

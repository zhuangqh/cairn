import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// A privacy-safe square card. The exact amount is deliberately omitted;
/// sharing reveals only the artifact name and the month it was earned.
struct AchievementShareButton: View {
    let presentation: AchievementPresentation

    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization

    var body: some View {
        ShareLink(
            item: shareItem,
            preview: SharePreview(shareItem.title)
        ) {
            Label("achievement.share.action", systemImage: "square.and.arrow.up")
        }
    }

    private var shareItem: AchievementShareItem {
        AchievementShareItem(
            family: presentation.family,
            stageKey: presentation.stageKey,
            title: String(
                localized: String.LocalizationValue(presentation.titleKey),
                bundle: localization.bundle
            ),
            month: AchievementFormatting.month(presentation.logicalMonth, locale: locale),
            neutralLine: String(localized: "achievement.share.neutral", bundle: localization.bundle)
        )
    }
}

private struct AchievementShareItem: Transferable, Sendable {
    let family: AchievementFamily
    let stageKey: String
    let title: String
    let month: String
    let neutralLine: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.renderedPNG()
        }
        .suggestedFileName("Cairn Achievement.png")
    }

    @MainActor
    private func renderedPNG() throws -> Data {
        let renderer = ImageRenderer(
            content: AchievementShareCardView(
                family: family,
                stageKey: stageKey,
                title: title,
                month: month,
                neutralLine: neutralLine
            )
            .frame(width: 1024, height: 1024)
        )
        renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
        renderer.scale = 1

        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else { throw ShareCardError.renderFailed }
        return data
        #else
        guard let data = renderer.uiImage?.pngData() else {
            throw ShareCardError.renderFailed
        }
        return data
        #endif
    }

    private enum ShareCardError: Error {
        case renderFailed
    }
}

private struct AchievementShareCardView: View {
    let family: AchievementFamily
    let stageKey: String
    let title: String
    let month: String
    let neutralLine: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x02100F), Color(hex: 0x0A2925), Color(hex: 0x071B19)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(hex: 0x35D8C8).opacity(0.16))
                .frame(width: 760, height: 760)
                .blur(radius: 100)
                .offset(x: 260, y: -310)

            Circle()
                .fill(Color(hex: 0x7559B9).opacity(0.13))
                .frame(width: 620, height: 620)
                .blur(radius: 120)
                .offset(x: -330, y: 360)

            VStack(spacing: 38) {
                Spacer(minLength: 70)

                AchievementBadgeView(
                    family: family,
                    stageKey: stageKey,
                    size: 300
                )

                VStack(spacing: 18) {
                    Text(title)
                        .font(.system(size: 62, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(neutralLine)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(month)
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(hex: 0x8DE9DE))
                }
                .padding(.horizontal, 80)

                Spacer()

                Text("CAIRN")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(7)
                    .foregroundStyle(Color.white.opacity(0.44))
                    .padding(.bottom, 64)
            }
        }
        .clipped()
    }
}

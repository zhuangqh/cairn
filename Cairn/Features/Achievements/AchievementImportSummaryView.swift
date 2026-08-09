import SwiftUI

struct AchievementImportSummaryView: View {
    let events: [AchievementPresentation]
    let onDone: () -> Void

    @Environment(LocalizationService.self) private var localization

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.notionBlue)
                        .frame(width: 86, height: 86)
                        .background(Color.notionBlue.opacity(0.10), in: Circle())

                    VStack(spacing: 6) {
                        Text("achievement.import.title", bundle: localization.bundle)
                            .font(.title2.bold())
                        Text("achievement.import.subtitle", bundle: localization.bundle)
                            .font(.subheadline)
                            .foregroundStyle(Color.notionInkSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 0) {
                        summaryRow(.wealthMilestone, titleKey: "achievement.family.wealth")
                        Divider().opacity(0.45)
                        summaryRow(.monthlyAscent, titleKey: "achievement.family.monthlyAscent")
                        Divider().opacity(0.45)
                        summaryRow(.timeMark, titleKey: "achievement.family.timeMark")
                    }
                    .glassCard(cornerRadius: 16, padding: 0)

                    NavigationLink {
                        AchievementJournalView()
                    } label: {
                        Label("achievement.import.openJournal", systemImage: "books.vertical.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.action.done", action: onDone)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    private func summaryRow(_ family: AchievementFamily, titleKey: String) -> some View {
        let count = events.filter { $0.family == family }.count
        let latest = events.first { $0.family == family }
        return HStack(spacing: 14) {
            AchievementBadgeView(
                family: family,
                stageKey: latest?.stageKey ?? fallbackStage(family),
                size: 44
            )
            .saturation(count == 0 ? 0.05 : 1)
            .opacity(count == 0 ? 0.38 : 1)
            Text(LocalizedStringKey(titleKey), bundle: localization.bundle)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(verbatim: "\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(count == 0 ? Color.notionInkMuted : Color.notionBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func fallbackStage(_ family: AchievementFamily) -> String {
        switch family {
        case .prologue: return "first-stone"
        case .wealthMilestone: return "wealth-0"
        case .monthlyAscent: return "ascent-0"
        case .timeMark: return "time-3"
        }
    }
}

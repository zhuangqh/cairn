import SwiftUI

/// Latest journal entry plus progress toward the next wealth milestone
/// (financial assets only), derived by `DashboardView`.
struct DashboardJournalSummary {
    let latest: AchievementPresentation?
    let nextThreshold: Decimal
    let homeCurrency: String
    let progress: Double
}

/// Journal entry row (§5.9) for the stacked dashboard: 44pt badge, eyebrow
/// line, then the latest achievement name with its month. `showsMilestone`
/// adds progress toward the next wealth milestone at the trailing edge.
struct DashboardJournalRow: View {
    @Environment(LocalizationService.self) private var localization

    let summary: DashboardJournalSummary
    let showsMilestone: Bool

    var body: some View {
        NavigationLink {
            AchievementJournalView()
        } label: {
            HStack(spacing: LedgerMetrics.columnSpacing) {
                DashboardJournalBadge(latest: summary.latest, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    DashboardJournalEyebrow(latest: summary.latest)
                        .font(.caption)
                    DashboardJournalTitle(latest: summary.latest)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsMilestone {
                    VStack(alignment: .trailing, spacing: 4) {
                        DashboardMilestoneLine(summary: summary, spread: false)
                        LedgerMeter(progress: summary.progress)
                            .frame(width: 140)
                        DashboardMilestoneFootnote()
                    }
                }

                LedgerChevron()
            }
            .frame(minHeight: 60)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { LedgerHairline() }
        .accessibilityHint(Text("achievement.dashboard.open", bundle: localization.bundle))
    }
}

/// Wide-layout companion to the hero: same eyebrow row and top inset as
/// `LedgerHero`, then badge + title, then milestone progress across the
/// column.
struct DashboardJournalPanel: View {
    @Environment(LocalizationService.self) private var localization

    let summary: DashboardJournalSummary

    var body: some View {
        NavigationLink {
            AchievementJournalView()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    DashboardJournalEyebrow(latest: summary.latest)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    LedgerChevron()
                }
                .frame(minHeight: 22)

                HStack(spacing: 14) {
                    DashboardJournalBadge(latest: summary.latest, size: 48)
                    DashboardJournalTitle(latest: summary.latest)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 10)

                VStack(alignment: .leading, spacing: 6) {
                    DashboardMilestoneLine(summary: summary, spread: true)
                    LedgerMeter(progress: summary.progress)
                    DashboardMilestoneFootnote()
                }
                .padding(.top, 12)
            }
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("achievement.dashboard.open", bundle: localization.bundle))
    }
}

// MARK: - Pieces

private struct DashboardJournalBadge: View {
    let latest: AchievementPresentation?
    let size: CGFloat

    var body: some View {
        AchievementBadgeView(
            family: latest?.family ?? .prologue,
            stageKey: latest?.stageKey ?? "first-stone",
            size: size
        )
        .saturation(latest == nil ? 0 : 1)
        .opacity(latest == nil ? 0.55 : 1)
    }
}

private struct DashboardJournalEyebrow: View {
    @Environment(LocalizationService.self) private var localization
    let latest: AchievementPresentation?

    var body: some View {
        Text(latest == nil ? "achievement.dashboard.eyebrow" : "achievement.dashboard.latest",
             bundle: localization.bundle)
            .foregroundStyle(Color.ink2)
    }
}

private struct DashboardJournalTitle: View {
    @Environment(LocalizationService.self) private var localization
    @Environment(\.locale) private var locale
    let latest: AchievementPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(
                    latest.map { LocalizedStringKey($0.titleKey) }
                        ?? LocalizedStringKey("achievement.firstStone.title"),
                    bundle: localization.bundle
                )
                .font(.headline)
                .foregroundStyle(Color.ink)

                if let latest {
                    Text(verbatim: AchievementFormatting.month(latest.logicalMonth, locale: locale))
                        .font(.footnote)
                        .foregroundStyle(Color.ink3)
                }
            }
            if latest == nil {
                Text("achievement.dashboard.empty", bundle: localization.bundle)
                    .font(.footnote)
                    .foregroundStyle(Color.ink3)
            }
        }
    }
}

/// "Next summit  US$1,000,000". `spread` pushes the amount to the trailing
/// edge for the full-width panel meter.
private struct DashboardMilestoneLine: View {
    @Environment(LocalizationService.self) private var localization
    @Environment(\.locale) private var locale
    let summary: DashboardJournalSummary
    let spread: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("achievement.dashboard.next", bundle: localization.bundle)
                .foregroundStyle(Color.ink3)
            if spread {
                Spacer(minLength: 0)
            }
            Text(
                summary.nextThreshold,
                format: .currency(code: summary.homeCurrency)
                    .precision(.fractionLength(0))
                    .locale(locale)
            )
            .monospacedDigit()
            .foregroundStyle(Color.ink)
        }
        .font(.footnote)
    }
}

private struct DashboardMilestoneFootnote: View {
    @Environment(LocalizationService.self) private var localization

    var body: some View {
        Text("achievement.dashboard.financialOnly", bundle: localization.bundle)
            .font(.caption2)
            .foregroundStyle(Color.ink3)
    }
}

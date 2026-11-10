import SwiftUI
import SwiftData

struct AchievementJournalView: View {
    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query private var events: [AchievementEvent]
    @State private var inspectedPresentation: AchievementPresentation?
    @State private var inspectedSourceFrame: CGRect = .zero
    @State private var inspectionProgress = 0.0
    @State private var sourceFrames: [String: CGRect] = [:]
    @State private var inspectionTask: Task<Void, Never>?

    private var presentations: [AchievementPresentation] {
        events
            .sorted {
                if $0.logicalMonth == $1.logicalMonth { return $0.unlockedAt > $1.unlockedAt }
                return $0.logicalMonth > $1.logicalMonth
            }
            .map(AchievementPresentation.init)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let featured = presentations.first {
                        featuredCard(featured)
                    } else {
                        emptyCard
                    }

                    familySection

                    if !presentations.isEmpty {
                        timelineSection
                    }
                }
                .pageHorizontalPadding()
                .padding(.bottom, 24)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            // Restore the journal continuously as the medal returns. Keeping
            // this tied to selection made the page jump from 22% to 100% only
            // after the closing animation had already finished.
            .opacity(1 - 0.78 * inspectionProgress)
            .allowsHitTesting(inspectedPresentation == nil)

            if let presentation = inspectedPresentation {
                AchievementMedalInspectionView(
                    presentation: presentation,
                    title: localized(presentation.titleKey),
                    requirement: inspectionRequirement(presentation),
                    sourceFrame: inspectedSourceFrame,
                    progress: inspectionProgress,
                    canClose: inspectionTask == nil && inspectionProgress == 1,
                    onClose: closeInspection
                )
                .zIndex(10)
            }
        }
        .background(AppBackground())
        .navigationTitle(Text("achievement.journal.title", bundle: localization.bundle))
        .onPreferenceChange(AchievementInspectionSourceFramesKey.self) { sourceFrames = $0 }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear {
            inspectionTask?.cancel()
        }
    }

    /// Latest achievement (§5.2 hero position): badge beside the copy, or
    /// above it at accessibility text sizes.
    private func featuredCard(_ presentation: AchievementPresentation) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    inspectButton(presentation, size: 84)
                    featuredCopy(presentation)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    inspectButton(presentation, size: 84)
                    featuredCopy(presentation)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectButton(_ presentation: AchievementPresentation, size: CGFloat) -> some View {
        Button {
            openInspection(presentation)
        } label: {
            if inspectedPresentation?.id == presentation.id {
                Color.clear
                    .frame(width: size * 1.4, height: size * 1.4)
            } else {
                ZStack {
                    AchievementBadgeView(presentation, size: size)
                }
                .frame(width: size * 1.4, height: size * 1.4)
                .achievementInspectionSource(id: featuredMatchedID(presentation))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(presentation.titleKey), bundle: localization.bundle))
        .accessibilityHint(Text("achievement.inspect.open", bundle: localization.bundle))
    }

    private func featuredCopy(_ presentation: AchievementPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("achievement.journal.featured", bundle: localization.bundle)
                Text(verbatim: " · " + AchievementFormatting.month(presentation.logicalMonth, locale: locale))
            }
            .font(.caption)
            .foregroundStyle(Color.ink3)

            Text(LocalizedStringKey(presentation.titleKey), bundle: localization.bundle)
                .font(.title.bold())
                .foregroundStyle(Color.ink)

            eventDescription(presentation)
                .font(.subheadline)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)

            AchievementShareButton(presentation: presentation)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var familySection: some View {
        let families: [AchievementPresentation?] = [
            latest(for: .wealthMilestone), currentAscent, latest(for: .timeMark)
        ]
        let lit = families.compactMap { $0 }.count
        return LedgerSection(Text("achievement.journal.families", bundle: localization.bundle)) {
            Text(verbatim: "\(String(localized: "achievement.journal.lit")) \(lit) / \(families.count)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.ink3)
        } content: {
            VStack(spacing: 0) {
                familyRow(
                    family: .wealthMilestone,
                    titleKey: "achievement.family.wealth",
                    subtitleKey: "achievement.family.wealth.subtitle",
                    current: families[0],
                    next: nextWealthLabel
                )
                LedgerHairline().padding(.leading, 40 + LedgerMetrics.columnSpacing)
                familyRow(
                    family: .monthlyAscent,
                    titleKey: "achievement.family.monthlyAscent",
                    subtitleKey: "achievement.family.monthlyAscent.subtitle",
                    current: families[1],
                    next: nil
                )
                LedgerHairline().padding(.leading, 40 + LedgerMetrics.columnSpacing)
                familyRow(
                    family: .timeMark,
                    titleKey: "achievement.family.timeMark",
                    subtitleKey: "achievement.family.timeMark.subtitle",
                    current: families[2],
                    next: nextTimeMarkLabel
                )
            }
        }
    }

    private func familyRow(
        family: AchievementFamily,
        titleKey: String,
        subtitleKey: String,
        current: AchievementPresentation?,
        next: String?
    ) -> some View {
        NavigationLink {
            AchievementFamilyDetailView(family: family)
        } label: {
            HStack(spacing: LedgerMetrics.columnSpacing) {
                AchievementBadgeView(
                    family: family,
                    stageKey: current?.stageKey ?? lockedStage(for: family),
                    size: 40
                )
                .saturation(current == nil ? 0 : 1)
                .opacity(current == nil ? 0.55 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(titleKey), bundle: localization.bundle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text(LocalizedStringKey(subtitleKey), bundle: localization.bundle)
                        .font(.caption)
                        .foregroundStyle(Color.ink2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    if let current {
                        eventValue(current)
                            .font(.callout.monospacedDigit().weight(.medium))
                            .foregroundStyle(Color.ink)
                    } else {
                        Text("achievement.locked", bundle: localization.bundle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.ink3)
                    }
                    if let next {
                        Text(verbatim: next)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.ink3)
                    }
                }

                LedgerChevron()
            }
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timelineSection: some View {
        LedgerSection(Text("achievement.journal.timeline", bundle: localization.bundle)) {
            VStack(spacing: 0) {
                ForEach(Array(presentations.enumerated()), id: \.element.id) { index, presentation in
                    HStack(spacing: 13) {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey(presentation.titleKey), bundle: localization.bundle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                            eventDescription(presentation)
                                .font(.caption)
                                .foregroundStyle(Color.ink2)
                        }
                        Spacer(minLength: 10)
                        Text(verbatim: AchievementFormatting.month(presentation.logicalMonth, locale: locale))
                            .font(.caption2)
                            .foregroundStyle(Color.ink3)
                    }
                    .padding(.vertical, 12)
                    if index < presentations.count - 1 {
                        LedgerHairline().padding(.leading, 20)
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            AchievementBadgeView(family: .prologue, stageKey: "first-stone", size: 82)
                .saturation(0.1)
                .opacity(0.45)
            Text("achievement.empty.title", bundle: localization.bundle)
                .font(.title3.bold())
            Text("achievement.empty.message", bundle: localization.bundle)
                .font(.subheadline)
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }

    private func latest(for family: AchievementFamily) -> AchievementPresentation? {
        presentations.first { $0.family == family }
    }

    private var currentAscent: AchievementPresentation? {
        presentations
            .filter { $0.family == .monthlyAscent && $0.currencyCode == homeCurrency }
            .max { ($0.observedAmount ?? 0) < ($1.observedAmount ?? 0) }
            ?? presentations.filter { $0.family == .monthlyAscent }
                .max { ($0.observedAmount ?? 0) < ($1.observedAmount ?? 0) }
    }

    private var nextWealthLabel: String? {
        let latest = presentations
            .filter { $0.family == .wealthMilestone }
            .compactMap { presentation -> Int? in
                AchievementService.wealthStageIndex(from: presentation.stageKey)
            }
            .max()
        let threshold = AchievementService.wealthThreshold(at: (latest ?? -1) + 1)
        return threshold.formatted(.currency(code: homeCurrency).precision(.fractionLength(0)).locale(locale))
    }

    private var nextTimeMarkLabel: String? {
        let earned = Set(presentations.filter { $0.family == .timeMark }.compactMap { Int($0.stageKey.split(separator: "-").last ?? "") })
        guard let next = AchievementService.timeMarkThresholds.first(where: { !earned.contains($0) }) else { return nil }
        return String(format: String(localized: "achievement.timeMark.next", bundle: localization.bundle), next)
    }

    private func lockedStage(for family: AchievementFamily) -> String {
        switch family {
        case .prologue: return "first-stone"
        case .wealthMilestone: return "wealth-0"
        case .monthlyAscent: return "ascent-0"
        case .timeMark: return "time-3"
        }
    }

    private func featuredMatchedID(_ presentation: AchievementPresentation) -> String {
        "journal-featured-medal-\(presentation.id)"
    }

    private func openInspection(_ presentation: AchievementPresentation) {
        guard inspectedPresentation == nil, inspectionTask == nil else { return }
        let matchedID = featuredMatchedID(presentation)
        guard let sourceFrame = sourceFrames[matchedID] else { return }
        inspectedSourceFrame = sourceFrame
        inspectionProgress = 0
        inspectedPresentation = presentation

        inspectionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let duration = reduceMotion ? 0.25 : 0.78
            withAnimation(reduceMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.18, 0.76, 0.22, 1, duration: duration)
            ) {
                inspectionProgress = 1
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            inspectionTask = nil
        }
    }

    private func closeInspection() {
        guard inspectedPresentation != nil, inspectionProgress == 1, inspectionTask == nil else { return }

        inspectionTask = Task { @MainActor in
            let duration = reduceMotion ? 0.25 : 0.72
            withAnimation(reduceMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.30, 0, 0.24, 1, duration: duration)
            ) {
                inspectionProgress = 0
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            inspectedPresentation = nil
            inspectionTask = nil
        }
    }

    private func inspectionRequirement(_ presentation: AchievementPresentation) -> String {
        switch presentation.family {
        case .prologue:
            return localized("achievement.firstStone.subtitle")
        case .wealthMilestone:
            guard let formatted = AchievementFormatting.amount(presentation, locale: locale) else {
                return localized("achievement.family.wealth.subtitle")
            }
            return String(
                format: String(localized: "achievement.wealth.description", bundle: localization.bundle),
                formatted
            )
        case .monthlyAscent:
            guard let formatted = AchievementFormatting.amount(presentation, locale: locale) else {
                return localized("achievement.family.monthlyAscent.subtitle")
            }
            return String(
                format: String(localized: "achievement.monthlyAscent.description", bundle: localization.bundle),
                formatted
            )
        case .timeMark:
            let months = NSDecimalNumber(decimal: presentation.observedAmount ?? 0).intValue
            return String(
                format: String(localized: "achievement.timeMark.description", bundle: localization.bundle),
                months
            )
        }
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: localization.bundle)
    }

    @ViewBuilder
    private func eventValue(_ presentation: AchievementPresentation) -> some View {
        if presentation.family == .timeMark, let amount = presentation.observedAmount {
            Text(verbatim: "\(NSDecimalNumber(decimal: amount).intValue)")
        } else if let formatted = AchievementFormatting.amount(presentation, locale: locale) {
            Text(verbatim: formatted)
        } else {
            Text(LocalizedStringKey(presentation.titleKey), bundle: localization.bundle)
        }
    }

    @ViewBuilder
    private func eventDescription(_ presentation: AchievementPresentation) -> some View {
        switch presentation.family {
        case .prologue:
            Text("achievement.firstStone.subtitle", bundle: localization.bundle)
        case .wealthMilestone:
            if let formatted = AchievementFormatting.amount(presentation, locale: locale) {
                Text(String(format: String(localized: "achievement.wealth.description", bundle: localization.bundle), formatted))
            }
        case .monthlyAscent:
            if let formatted = AchievementFormatting.amount(presentation, locale: locale) {
                Text(String(format: String(localized: "achievement.monthlyAscent.description", bundle: localization.bundle), formatted))
            }
        case .timeMark:
            let months = NSDecimalNumber(decimal: presentation.observedAmount ?? 0).intValue
            Text(String(format: String(localized: "achievement.timeMark.description", bundle: localization.bundle), months))
        }
    }
}

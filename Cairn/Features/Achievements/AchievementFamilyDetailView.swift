import SwiftUI
import SwiftData

/// A family's complete progression: earned artifacts remain fully materialized,
/// while upcoming stages stay visible as quiet stone silhouettes.
struct AchievementFamilyDetailView: View {
    let family: AchievementFamily

    @Environment(\.locale) private var locale
    @Environment(LocalizationService.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @Query private var events: [AchievementEvent]
    @State private var selectedAscentCurrency = ""
    @State private var inspectedMedal: InspectionSelection?
    @State private var inspectedSourceFrame: CGRect = .zero
    @State private var inspectionProgress = 0.0
    @State private var sourceFrames: [String: CGRect] = [:]
    @State private var inspectionTask: Task<Void, Never>?

    private struct Stage: Identifiable {
        let id: String
        let stageKey: String
        let title: String
        let requirement: String
        let earned: AchievementPresentation?
    }

    private struct InspectionSelection: Identifiable {
        let id: String
        let matchedID: String
        let presentation: AchievementPresentation
        let title: String
        let requirement: String
    }

    private var allPresentations: [AchievementPresentation] {
        events
            .map(AchievementPresentation.init)
            .sorted {
                if $0.logicalMonth == $1.logicalMonth { return $0.unlockedAt > $1.unlockedAt }
                return $0.logicalMonth > $1.logicalMonth
            }
    }

    private var familyPresentations: [AchievementPresentation] {
        let matches = allPresentations.filter { $0.family == family }
        guard family == .monthlyAscent else { return matches }
        return matches.filter { $0.currencyCode == effectiveAscentCurrency }
    }

    private var ascentCurrencies: [String] {
        Set(allPresentations.filter { $0.family == .monthlyAscent }.compactMap(\.currencyCode))
            .sorted()
    }

    private var effectiveAscentCurrency: String {
        if ascentCurrencies.contains(selectedAscentCurrency) { return selectedAscentCurrency }
        if ascentCurrencies.contains(homeCurrency) { return homeCurrency }
        return ascentCurrencies.first ?? homeCurrency
    }

    private var stages: [Stage] {
        switch family {
        case .wealthMilestone:
            return wealthStages
        case .monthlyAscent:
            return ascentStages
        case .timeMark:
            return timeStages
        case .prologue:
            return []
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if family == .monthlyAscent, ascentCurrencies.count > 1 {
                        Picker("achievement.detail.currency", selection: $selectedAscentCurrency) {
                            ForEach(ascentCurrencies, id: \.self) { currency in
                                Text(verbatim: currency).tag(currency)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    sectionHeader("achievement.detail.stages")

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(stages) { stage in
                            stageCard(stage)
                        }
                    }

                    if !familyPresentations.isEmpty {
                        sectionHeader("achievement.detail.history")
                        historyCard
                    }
                }
                .pageHorizontalPadding()
                .padding(.vertical, 20)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            // Share the inspection progress with the underlying page so its
            // brightness returns in step with the shrinking medal and backdrop.
            .opacity(1 - 0.78 * inspectionProgress)
            .allowsHitTesting(inspectedMedal == nil)

            if let selection = inspectedMedal {
                AchievementMedalInspectionView(
                    presentation: selection.presentation,
                    title: selection.title,
                    requirement: selection.requirement,
                    sourceFrame: inspectedSourceFrame,
                    progress: inspectionProgress,
                    canClose: inspectionTask == nil && inspectionProgress == 1,
                    onClose: closeInspection
                )
                .zIndex(10)
            }
        }
        .background(AppBackground())
        .onPreferenceChange(AchievementInspectionSourceFramesKey.self) { sourceFrames = $0 }
        .navigationTitle(Text(LocalizedStringKey(familyTitleKey), bundle: localization.bundle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard family == .monthlyAscent, selectedAscentCurrency.isEmpty else { return }
            selectedAscentCurrency = effectiveAscentCurrency
        }
        .onDisappear {
            inspectionTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 22) {
            if let featuredPresentation {
                Button {
                    openInspection(
                        InspectionSelection(
                            id: "header-\(featuredPresentation.id)",
                            matchedID: "header-medal-\(featuredPresentation.id)",
                            presentation: featuredPresentation,
                            title: localized(featuredPresentation.titleKey),
                            requirement: historyValue(featuredPresentation) ?? localized(familySubtitleKey)
                        )
                    )
                } label: {
                    sourceBadge(
                        family: family,
                        stageKey: featuredPresentation.stageKey,
                        size: 88,
                        matchedID: "header-medal-\(featuredPresentation.id)",
                        isEarned: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("achievement.inspect.open", bundle: localization.bundle))
            } else {
                AchievementBadgeView(
                    family: family,
                    stageKey: fallbackStageKey,
                    size: 88
                )
                .saturation(0)
                .opacity(0.40)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(familyTitleKey), bundle: localization.bundle)
                    .font(.title2.bold())
                    .foregroundStyle(Color.notionInk)
                Text(LocalizedStringKey(familySubtitleKey), bundle: localization.bundle)
                    .font(.subheadline)
                    .foregroundStyle(Color.notionInkSecondary)
                Text(
                    String(
                        format: String(localized: "achievement.detail.progress", bundle: localization.bundle),
                        stages.filter { $0.earned != nil }.count,
                        stages.count
                    )
                )
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.notionBlue)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 0)
    }

    @ViewBuilder
    private func stageCard(_ stage: Stage) -> some View {
        let isEarned = stage.earned != nil
        if isEarned {
            Button {
                guard let presentation = stage.earned else { return }
                openInspection(
                    InspectionSelection(
                        id: stage.id,
                        matchedID: stageMatchedID(stage),
                        presentation: presentation,
                        title: stage.title,
                        requirement: stage.requirement
                    )
                )
            } label: {
                stageCardContent(stage, isEarned: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("achievement.inspect.open", bundle: localization.bundle))
        } else {
            stageCardContent(stage, isEarned: false)
        }
    }

    private func stageCardContent(_ stage: Stage, isEarned: Bool) -> some View {
        VStack(spacing: 10) {
            sourceBadge(
                family: family,
                stageKey: stage.stageKey,
                size: 62,
                matchedID: stageMatchedID(stage),
                isEarned: isEarned
            )

            VStack(spacing: 4) {
                Text(verbatim: stage.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isEarned ? Color.notionInk : Color.notionInkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(verbatim: stage.requirement)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.notionInkSecondary)
                    .multilineTextAlignment(.center)

                if let earned = stage.earned {
                    Text(verbatim: AchievementFormatting.month(earned.logicalMonth, locale: locale))
                        .font(.caption2)
                        .foregroundStyle(Color.notionBlue)
                } else {
                    Text("achievement.detail.future", bundle: localization.bundle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.notionInkMuted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 196)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isEarned ? Color.notionSurface : Color.notionSurfaceAlt.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.notionBorder.opacity(isEarned ? 1 : 0.55), lineWidth: 0.8)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var historyCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(familyPresentations.enumerated()), id: \.element.id) { index, presentation in
                HStack(spacing: 12) {
                    Button {
                        openInspection(
                            InspectionSelection(
                                id: "history-\(presentation.id)",
                                matchedID: "history-medal-\(presentation.id)",
                                presentation: presentation,
                                title: localized(presentation.titleKey),
                                requirement: historyValue(presentation) ?? localized(familySubtitleKey)
                            )
                        )
                    } label: {
                        sourceBadge(
                            family: presentation.family,
                            stageKey: presentation.stageKey,
                            size: 36,
                            matchedID: "history-medal-\(presentation.id)",
                            isEarned: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("achievement.inspect.open", bundle: localization.bundle))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(presentation.titleKey), bundle: localization.bundle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.notionInk)
                        if let value = historyValue(presentation) {
                            Text(verbatim: value)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.notionInkSecondary)
                        }
                    }

                    Spacer(minLength: 10)

                    Text(verbatim: AchievementFormatting.month(presentation.logicalMonth, locale: locale))
                        .font(.caption2)
                        .foregroundStyle(Color.notionInkMuted)
                }
                .padding(.vertical, 11)

                if index < familyPresentations.count - 1 {
                    Divider().opacity(0.45).padding(.leading, 62)
                }
            }
        }
        .padding(.horizontal, 16)
        .glassCard(cornerRadius: 16, padding: 0)
    }

    private var wealthStages: [Stage] {
        let byIndex = Dictionary(
            uniqueKeysWithValues: familyPresentations.compactMap { presentation in
                AchievementService.wealthStageIndex(from: presentation.stageKey).map { ($0, presentation) }
            }
        )
        let highestEarned = byIndex.keys.max() ?? -1
        let upperBound = max(6, highestEarned + 3)

        return (0...upperBound).map { index in
            let stageKey = "wealth-\(index)"
            let presentation = byIndex[index]
            let currency = presentation?.currencyCode ?? homeCurrency
            let threshold = AchievementService.wealthThreshold(at: index)
            return Stage(
                id: stageKey,
                stageKey: stageKey,
                title: localized(wealthTitleKey(index)),
                requirement: threshold.formatted(
                    .currency(code: currency).precision(.fractionLength(0)).locale(locale)
                ),
                earned: presentation
            )
        }
    }

    private var ascentStages: [Stage] {
        let ordered = familyPresentations.sorted { $0.logicalMonth < $1.logicalMonth }
        let record = ordered.compactMap(\.observedAmount).max() ?? 0
        let highestMaterial = AchievementService.monthlyAscentMaterialIndex(for: record)
        let upperBound = max(6, highestMaterial + 3)

        return (0...upperBound).map { index in
            let threshold = ascentThreshold(for: index)
            let earned = ordered.first { presentation in
                guard let amount = presentation.observedAmount else { return false }
                return index == 0 ? amount > 0 : amount >= threshold
            }
            let title = index == 0
                ? localized("achievement.detail.firstRecord")
                : threshold.formatted(
                    .currency(code: effectiveAscentCurrency)
                        .precision(.fractionLength(0))
                        .locale(locale)
                )
            let requirement = index == 0
                ? localized("achievement.detail.firstRecord.requirement")
                : localized("achievement.detail.ascentRequirement")
            return Stage(
                id: "ascent-tier-\(index)",
                stageKey: "ascent-\(index)",
                title: title,
                requirement: requirement,
                earned: earned
            )
        }
    }

    private var timeStages: [Stage] {
        let byThreshold = Dictionary(
            uniqueKeysWithValues: familyPresentations.compactMap { presentation -> (Int, AchievementPresentation)? in
                guard let threshold = Int(presentation.stageKey.split(separator: "-").last ?? "") else { return nil }
                return (threshold, presentation)
            }
        )
        return AchievementService.timeMarkThresholds.map { threshold in
            Stage(
                id: "time-\(threshold)",
                stageKey: "time-\(threshold)",
                title: String(
                    format: String(localized: "achievement.detail.timeStage", bundle: localization.bundle),
                    threshold
                ),
                requirement: localized("achievement.detail.timeRequirement"),
                earned: byThreshold[threshold]
            )
        }
    }

    private var featuredPresentation: AchievementPresentation? {
        switch family {
        case .monthlyAscent:
            return familyPresentations.max { ($0.observedAmount ?? 0) < ($1.observedAmount ?? 0) }
        default:
            return familyPresentations.first
        }
    }

    private var familyTitleKey: String {
        switch family {
        case .wealthMilestone: return "achievement.family.wealth"
        case .monthlyAscent: return "achievement.family.monthlyAscent"
        case .timeMark: return "achievement.family.timeMark"
        case .prologue: return "achievement.firstStone.title"
        }
    }

    private var familySubtitleKey: String {
        switch family {
        case .wealthMilestone: return "achievement.family.wealth.subtitle"
        case .monthlyAscent: return "achievement.family.monthlyAscent.subtitle"
        case .timeMark: return "achievement.family.timeMark.subtitle"
        case .prologue: return "achievement.firstStone.subtitle"
        }
    }

    private var fallbackStageKey: String {
        switch family {
        case .wealthMilestone: return "wealth-0"
        case .monthlyAscent: return "ascent-0"
        case .timeMark: return "time-3"
        case .prologue: return "first-stone"
        }
    }

    private func ascentThreshold(for materialIndex: Int) -> Decimal {
        guard materialIndex > 0 else { return 0 }
        return AchievementService.wealthThreshold(at: materialIndex - 1) / 10
    }

    private func wealthTitleKey(_ index: Int) -> String {
        switch index {
        case 0: return "achievement.wealth.stage.100k"
        case 1: return "achievement.wealth.stage.200k"
        case 2: return "achievement.wealth.stage.500k"
        case 3: return "achievement.wealth.stage.1m"
        case 4: return "achievement.wealth.stage.2m"
        case 5: return "achievement.wealth.stage.5m"
        case 6: return "achievement.wealth.stage.10m"
        default: return "achievement.wealth.stage.generic"
        }
    }

    private func historyValue(_ presentation: AchievementPresentation) -> String? {
        if presentation.family == .timeMark {
            let months = NSDecimalNumber(decimal: presentation.observedAmount ?? 0).intValue
            return String(
                format: String(localized: "achievement.timeMark.description", bundle: localization.bundle),
                months
            )
        }
        return AchievementFormatting.amount(presentation, locale: locale)
    }

    private func stageMatchedID(_ stage: Stage) -> String {
        "stage-medal-\(stage.id)"
    }

    @ViewBuilder
    private func sourceBadge(
        family: AchievementFamily,
        stageKey: String,
        size: CGFloat,
        matchedID: String,
        isEarned: Bool
    ) -> some View {
        if inspectedMedal?.matchedID == matchedID {
            Color.clear
                .frame(width: size * 1.4, height: size * 1.4)
        } else {
            ZStack {
                AchievementBadgeView(
                    family: family,
                    stageKey: stageKey,
                    size: size
                )
            }
            .frame(width: size * 1.4, height: size * 1.4)
            .achievementInspectionSource(id: matchedID)
            .saturation(isEarned ? 1 : 0)
            .opacity(isEarned ? 1 : 0.34)
        }
    }

    private func openInspection(_ selection: InspectionSelection) {
        guard inspectedMedal == nil, inspectionTask == nil else { return }
        guard let sourceFrame = sourceFrames[selection.matchedID] else { return }
        inspectedSourceFrame = sourceFrame
        inspectionProgress = 0
        inspectedMedal = selection

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
        guard inspectedMedal != nil, inspectionProgress == 1, inspectionTask == nil else { return }

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
            inspectedMedal = nil
            inspectionTask = nil
        }
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: localization.bundle)
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(LocalizedStringKey(key), bundle: localization.bundle)
            .font(.caption.weight(.bold))
            .tracking(0.65)
            .textCase(.uppercase)
            .foregroundStyle(Color.notionInkSecondary)
    }
}

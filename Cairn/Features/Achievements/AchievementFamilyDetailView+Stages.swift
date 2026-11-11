import SwiftUI

// MARK: - Stage ladder for AchievementFamilyDetailView
//
// Extracted to keep the main view's type body small; builds the earned and
// upcoming stages shown in the family detail grid.

extension AchievementFamilyDetailView {
    struct Stage: Identifiable {
        let id: String
        let stageKey: String
        let title: String
        let requirement: String
        let earned: AchievementPresentation?
    }

    /// Builds one family's stage ladder from its earned presentations.
    @MainActor
    struct StageBuilder {
        let presentations: [AchievementPresentation]
        let homeCurrency: String
        let ascentCurrency: String
        let locale: Locale
        let bundle: Bundle

        func stages(for family: AchievementFamily) -> [Stage] {
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

        private var wealthStages: [Stage] {
            let byIndex = Dictionary(
                uniqueKeysWithValues: presentations.compactMap { presentation in
                    AchievementService.wealthStageIndex(from: presentation.stageKey).map { ($0, presentation) }
                }
            )
            return (0..<AchievementService.wealthStageCount).map { index in
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
            let ordered = presentations.sorted { $0.logicalMonth < $1.logicalMonth }
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
                        .currency(code: ascentCurrency)
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
                uniqueKeysWithValues: presentations.compactMap { presentation -> (Int, AchievementPresentation)? in
                    guard let threshold = Int(presentation.stageKey.split(separator: "-").last ?? "") else { return nil }
                    return (threshold, presentation)
                }
            )
            return AchievementService.timeMarkThresholds.map { threshold in
                Stage(
                    id: "time-\(threshold)",
                    stageKey: "time-\(threshold)",
                    title: String(
                        format: String(localized: "achievement.detail.timeStage", bundle: bundle),
                        threshold
                    ),
                    requirement: localized("achievement.detail.timeRequirement"),
                    earned: byThreshold[threshold]
                )
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

        private func localized(_ key: String) -> String {
            String(localized: String.LocalizationValue(key), bundle: bundle)
        }
    }
}

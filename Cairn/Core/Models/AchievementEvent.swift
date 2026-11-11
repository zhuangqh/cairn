import Foundation
import SwiftData

enum AchievementFamily: String, Codable, CaseIterable, Sendable {
    case prologue
    case wealthMilestone
    case monthlyAscent
    case timeMark
}

enum AchievementSource: String, Codable, Sendable {
    case live
    case imported
    case confirmedEstimate
}

/// A durable, auditable achievement occurrence. The collection can always be
/// replayed from `PortfolioSnapshot` rows; these records preserve the original
/// unlock time and make the UI inexpensive to render.
@Model
final class AchievementEvent {
    var id: UUID = UUID()
    /// Stable identity produced by the deterministic evaluator.
    var eventKey: String = ""
    var familyRawValue: String = AchievementFamily.prologue.rawValue
    var stageKey: String = ""
    var logicalMonth: Date = Date()
    var unlockedAt: Date = Date()
    var currencyCode: String?
    var observedAmount: Decimal?
    var sourceRawValue: String = AchievementSource.live.rawValue
    var sourceSnapshotIDsData: Data = Data()
    var definitionVersion: Int = 1

    init(
        eventKey: String,
        family: AchievementFamily,
        stageKey: String,
        logicalMonth: Date,
        unlockedAt: Date = .now,
        currencyCode: String? = nil,
        observedAmount: Decimal? = nil,
        source: AchievementSource = .live,
        sourceSnapshotIDs: [UUID] = [],
        definitionVersion: Int = 1
    ) {
        self.id = UUID()
        self.eventKey = eventKey
        self.familyRawValue = family.rawValue
        self.stageKey = stageKey
        self.logicalMonth = Snapshot.normalize(logicalMonth)
        self.unlockedAt = unlockedAt
        self.currencyCode = currencyCode
        self.observedAmount = observedAmount
        self.sourceRawValue = source.rawValue
        self.sourceSnapshotIDsData = (try? JSONEncoder().encode(sourceSnapshotIDs)) ?? Data()
        self.definitionVersion = definitionVersion
    }

    var family: AchievementFamily {
        get { AchievementFamily(rawValue: familyRawValue) ?? .prologue }
        set { familyRawValue = newValue.rawValue }
    }

    var source: AchievementSource {
        get { AchievementSource(rawValue: sourceRawValue) ?? .live }
        set { sourceRawValue = newValue.rawValue }
    }

    var sourceSnapshotIDs: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: sourceSnapshotIDsData)) ?? [] }
        set { sourceSnapshotIDsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

struct AchievementPresentation: Identifiable, Hashable, Sendable {
    let id: String
    let family: AchievementFamily
    let stageKey: String
    let logicalMonth: Date
    let unlockedAt: Date
    let currencyCode: String?
    let observedAmount: Decimal?
    let source: AchievementSource

    init(_ event: AchievementEvent) {
        self.id = event.eventKey
        self.family = event.family
        self.stageKey = event.stageKey
        self.logicalMonth = event.logicalMonth
        self.unlockedAt = event.unlockedAt
        self.currencyCode = event.currencyCode
        self.observedAmount = event.observedAmount
        self.source = event.source
    }

    var titleKey: String {
        switch family {
        case .prologue:
            return "achievement.firstStone.title"
        case .wealthMilestone:
            switch stageKey {
            case "wealth-0": return "achievement.wealth.stage.100k"
            case "wealth-1": return "achievement.wealth.stage.200k"
            case "wealth-2": return "achievement.wealth.stage.500k"
            case "wealth-3": return "achievement.wealth.stage.1m"
            case "wealth-4": return "achievement.wealth.stage.2m"
            case "wealth-5": return "achievement.wealth.stage.5m"
            case "wealth-6": return "achievement.wealth.stage.10m"
            default: return "achievement.wealth.stage.generic"
            }
        case .monthlyAscent:
            return "achievement.monthlyAscent.title"
        case .timeMark:
            return "achievement.timeMark.title"
        }
    }

    var systemImage: String {
        switch family {
        case .prologue: return "seal.fill"
        case .wealthMilestone: return "mountain.2.fill"
        case .monthlyAscent: return "arrow.up.right"
        case .timeMark: return "circle.hexagongrid.fill"
        }
    }
}

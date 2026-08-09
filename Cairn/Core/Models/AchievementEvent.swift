import Foundation
import SwiftData

public enum AchievementFamily: String, Codable, CaseIterable, Sendable {
    case prologue
    case wealthMilestone
    case monthlyAscent
    case timeMark
}

public enum AchievementSource: String, Codable, Sendable {
    case live
    case imported
    case confirmedEstimate
}

/// A durable, auditable achievement occurrence. The collection can always be
/// replayed from `PortfolioSnapshot` rows; these records preserve the original
/// unlock time and make the UI inexpensive to render.
@Model
public final class AchievementEvent {
    public var id: UUID = UUID()
    /// Stable identity produced by the deterministic evaluator.
    public var eventKey: String = ""
    public var familyRawValue: String = AchievementFamily.prologue.rawValue
    public var stageKey: String = ""
    public var logicalMonth: Date = Date()
    public var unlockedAt: Date = Date()
    public var currencyCode: String?
    public var observedAmount: Decimal?
    public var sourceRawValue: String = AchievementSource.live.rawValue
    public var sourceSnapshotIDsData: Data = Data()
    public var definitionVersion: Int = 1

    public init(
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

    public var family: AchievementFamily {
        get { AchievementFamily(rawValue: familyRawValue) ?? .prologue }
        set { familyRawValue = newValue.rawValue }
    }

    public var source: AchievementSource {
        get { AchievementSource(rawValue: sourceRawValue) ?? .live }
        set { sourceRawValue = newValue.rawValue }
    }

    public var sourceSnapshotIDs: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: sourceSnapshotIDsData)) ?? [] }
        set { sourceSnapshotIDsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

public struct AchievementPresentation: Identifiable, Hashable, Sendable {
    public let id: String
    public let family: AchievementFamily
    public let stageKey: String
    public let logicalMonth: Date
    public let unlockedAt: Date
    public let currencyCode: String?
    public let observedAmount: Decimal?
    public let source: AchievementSource

    public init(_ event: AchievementEvent) {
        self.id = event.eventKey
        self.family = event.family
        self.stageKey = event.stageKey
        self.logicalMonth = event.logicalMonth
        self.unlockedAt = event.unlockedAt
        self.currencyCode = event.currencyCode
        self.observedAmount = event.observedAmount
        self.source = event.source
    }

    public var titleKey: String {
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

    public var systemImage: String {
        switch family {
        case .prologue: return "seal.fill"
        case .wealthMilestone: return "mountain.2.fill"
        case .monthlyAscent: return "arrow.up.right"
        case .timeMark: return "circle.hexagongrid.fill"
        }
    }
}

import Foundation
import SwiftData

@MainActor
public enum AchievementService {
    public static let definitionVersion = 1
    public static let timeMarkThresholds = [3, 6, 12, 24, 60]

    public struct EvaluationResult: Sendable {
        public var created: [AchievementPresentation]
        public var removedCount: Int
    }

    private struct Candidate {
        var eventKey: String
        var family: AchievementFamily
        var stageKey: String
        var logicalMonth: Date
        var currencyCode: String?
        var observedAmount: Decimal?
        var sourceSnapshotIDs: [UUID]
    }

    /// Replays the complete explicit monthly history, preserving matching
    /// persisted events and removing events invalidated by factual edits.
    @discardableResult
    public static func recompute(
        in context: ModelContext,
        source: AchievementSource = .live,
        now: Date = .now
    ) throws -> EvaluationResult {
        let snapshots = ((try? context.fetch(FetchDescriptor<PortfolioSnapshot>())) ?? [])
            .sorted(by: snapshotOrder)
        let candidates = evaluate(snapshots)
        let candidateKeys = Set(candidates.map(\.eventKey))

        let existing = (try? context.fetch(FetchDescriptor<AchievementEvent>())) ?? []
        var firstExistingByKey: [String: AchievementEvent] = [:]
        var removedCount = 0

        for event in existing {
            if firstExistingByKey[event.eventKey] == nil, candidateKeys.contains(event.eventKey) {
                firstExistingByKey[event.eventKey] = event
            } else {
                context.delete(event)
                removedCount += 1
            }
        }

        var created: [AchievementPresentation] = []
        for candidate in candidates {
            if let event = firstExistingByKey[candidate.eventKey] {
                event.family = candidate.family
                event.stageKey = candidate.stageKey
                event.logicalMonth = candidate.logicalMonth
                event.currencyCode = candidate.currencyCode
                event.observedAmount = candidate.observedAmount
                event.sourceSnapshotIDs = candidate.sourceSnapshotIDs
                event.definitionVersion = definitionVersion
            } else {
                let event = AchievementEvent(
                    eventKey: candidate.eventKey,
                    family: candidate.family,
                    stageKey: candidate.stageKey,
                    logicalMonth: candidate.logicalMonth,
                    unlockedAt: now,
                    currencyCode: candidate.currencyCode,
                    observedAmount: candidate.observedAmount,
                    source: source,
                    sourceSnapshotIDs: candidate.sourceSnapshotIDs,
                    definitionVersion: definitionVersion
                )
                context.insert(event)
                created.append(AchievementPresentation(event))
            }
        }

        try context.save()
        created.sort { lhs, rhs in
            if lhs.logicalMonth == rhs.logicalMonth {
                return presentationPriority(lhs.family) < presentationPriority(rhs.family)
            }
            return lhs.logicalMonth < rhs.logicalMonth
        }
        return EvaluationResult(created: created, removedCount: removedCount)
    }

    public static func allPresentations(in context: ModelContext) -> [AchievementPresentation] {
        return ((try? context.fetch(FetchDescriptor<AchievementEvent>())) ?? [])
            .sorted {
                if $0.logicalMonth == $1.logicalMonth { return $0.unlockedAt > $1.unlockedAt }
                return $0.logicalMonth > $1.logicalMonth
            }
            .map(AchievementPresentation.init)
    }

    public static func nextWealthThreshold(after amount: Decimal) -> Decimal {
        for index in 0..<60 {
            let threshold = wealthThreshold(at: index)
            if threshold > amount { return threshold }
        }
        return amount
    }

    public static func wealthThreshold(at index: Int) -> Decimal {
        let bases = [1, 2, 5]
        let safeIndex = max(0, index)
        let exponent = 5 + (safeIndex / 3)
        return Decimal(bases[safeIndex % 3]) * powerOfTen(exponent)
    }

    public static func wealthStageIndex(from stageKey: String) -> Int? {
        guard stageKey.hasPrefix("wealth-") else { return nil }
        return Int(stageKey.dropFirst("wealth-".count))
    }

    public static func monthlyAscentMaterialIndex(for amount: Decimal) -> Int {
        guard amount > 0 else { return 0 }
        var result = 0
        for index in 0..<60 {
            let threshold = Decimal(10_000) * wealthThreshold(at: index) / Decimal(100_000)
            if amount >= threshold { result = index + 1 } else { break }
        }
        return result
    }

    private static func evaluate(_ snapshots: [PortfolioSnapshot]) -> [Candidate] {
        guard let first = snapshots.first else { return [] }
        var output: [Candidate] = [
            Candidate(
                eventKey: "first-stone",
                family: .prologue,
                stageKey: "first-stone",
                logicalMonth: first.periodMonth,
                currencyCode: first.homeCurrency,
                observedAmount: first.totalAmount,
                sourceSnapshotIDs: [first.id]
            )
        ]

        output.append(contentsOf: wealthCandidates(snapshots))
        output.append(contentsOf: ascentCandidates(snapshots))
        output.append(contentsOf: timeMarkCandidates(snapshots))
        return output.sorted { lhs, rhs in
            if lhs.logicalMonth == rhs.logicalMonth {
                return lhs.eventKey < rhs.eventKey
            }
            return lhs.logicalMonth < rhs.logicalMonth
        }
    }

    private static func wealthCandidates(_ snapshots: [PortfolioSnapshot]) -> [Candidate] {
        let maximum = snapshots.map(\.totalAmount).max() ?? 0
        guard maximum >= wealthThreshold(at: 0) else { return [] }

        var thresholdCount = 0
        while thresholdCount < 60, wealthThreshold(at: thresholdCount) <= maximum {
            thresholdCount += 1
        }

        var awarded = Set<Int>()
        var output: [Candidate] = []
        for snapshot in snapshots {
            for index in 0..<thresholdCount where !awarded.contains(index) {
                let threshold = wealthThreshold(at: index)
                guard snapshot.totalAmount >= threshold else { continue }
                awarded.insert(index)
                output.append(Candidate(
                    eventKey: "wealth-\(index)",
                    family: .wealthMilestone,
                    stageKey: "wealth-\(index)",
                    logicalMonth: snapshot.periodMonth,
                    currencyCode: snapshot.homeCurrency,
                    observedAmount: threshold,
                    sourceSnapshotIDs: [snapshot.id]
                ))
            }
        }
        return output
    }

    private static func ascentCandidates(_ snapshots: [PortfolioSnapshot]) -> [Candidate] {
        let grouped = Dictionary(grouping: snapshots, by: \.homeCurrency)
        var output: [Candidate] = []

        for (currency, currencySnapshots) in grouped {
            let ordered = currencySnapshots.sorted(by: snapshotOrder)
            var best: Decimal = 0
            for index in 1..<ordered.count {
                let previous = ordered[index - 1]
                let current = ordered[index]
                guard monthsApart(previous.periodMonth, current.periodMonth) == 1 else { continue }
                let delta = current.totalAmount - previous.totalAmount
                guard delta > best, delta > 0 else { continue }
                best = delta
                let monthKey = monthIdentifier(current.periodMonth)
                let materialIndex = monthlyAscentMaterialIndex(for: delta)
                output.append(Candidate(
                    eventKey: "ascent-\(currency)-\(monthKey)",
                    family: .monthlyAscent,
                    stageKey: "ascent-\(materialIndex)",
                    logicalMonth: current.periodMonth,
                    currencyCode: currency,
                    observedAmount: delta,
                    sourceSnapshotIDs: [previous.id, current.id]
                ))
            }
        }
        return output
    }

    private static func timeMarkCandidates(_ snapshots: [PortfolioSnapshot]) -> [Candidate] {
        let snapshotsByMonth = Dictionary(grouping: snapshots, by: \.periodMonth)
        let months = snapshotsByMonth.keys.sorted()
        guard !months.isEmpty else { return [] }

        var output: [Candidate] = []
        var awarded = Set<Int>()
        var run = 0
        var previous: Date?

        for month in months {
            if let previous, monthsApart(previous, month) == 1 {
                run += 1
            } else {
                run = 1
            }
            previous = month

            for threshold in timeMarkThresholds where run >= threshold && !awarded.contains(threshold) {
                awarded.insert(threshold)
                let sourceID = snapshotsByMonth[month]?.sorted(by: snapshotOrder).first?.id
                output.append(Candidate(
                    eventKey: "time-\(threshold)",
                    family: .timeMark,
                    stageKey: "time-\(threshold)",
                    logicalMonth: month,
                    currencyCode: nil,
                    observedAmount: Decimal(threshold),
                    sourceSnapshotIDs: sourceID.map { [$0] } ?? []
                ))
            }
        }
        return output
    }

    private static func snapshotOrder(_ lhs: PortfolioSnapshot, _ rhs: PortfolioSnapshot) -> Bool {
        if lhs.periodMonth == rhs.periodMonth {
            if lhs.recordedAt == rhs.recordedAt { return lhs.homeCurrency < rhs.homeCurrency }
            return lhs.recordedAt < rhs.recordedAt
        }
        return lhs.periodMonth < rhs.periodMonth
    }

    private static func monthsApart(_ lhs: Date, _ rhs: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.dateComponents([.month], from: Snapshot.normalize(lhs), to: Snapshot.normalize(rhs)).month ?? 0
    }

    private static func monthIdentifier(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func powerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(Decimal(1)) { result, _ in result * 10 }
    }

    private static func presentationPriority(_ family: AchievementFamily) -> Int {
        switch family {
        case .wealthMilestone: return 0
        case .monthlyAscent: return 1
        case .timeMark: return 2
        case .prologue: return 3
        }
    }
}

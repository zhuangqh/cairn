import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class AchievementServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() {
        container = nil
    }

    func testFirstSnapshotBackfillsFirstStoneAndWealthLadder() throws {
        let context = container.mainContext
        context.insert(snapshot("2026-01-01", total: 1_100_000, currency: "AUD"))
        try context.save()

        let result = try AchievementService.recompute(in: context)
        let events = try context.fetch(FetchDescriptor<AchievementEvent>())

        XCTAssertEqual(result.created.filter { $0.family == .prologue }.count, 1)
        XCTAssertEqual(events.filter { $0.family == .wealthMilestone }.count, 4)
        XCTAssertEqual(
            Set(events.filter { $0.family == .wealthMilestone }.map(\.stageKey)),
            Set(["wealth-0", "wealth-1", "wealth-2", "wealth-3"])
        )
    }

    func testMonthlyAscentRequiresAdjacentMonthsAndTracksPersonalBests() throws {
        let context = container.mainContext
        context.insert(snapshot("2026-01-01", total: 100_000, currency: "AUD"))
        context.insert(snapshot("2026-02-01", total: 125_000, currency: "AUD"))
        context.insert(snapshot("2026-03-01", total: 140_000, currency: "AUD"))
        context.insert(snapshot("2026-04-01", total: 190_000, currency: "AUD"))
        try context.save()

        _ = try AchievementService.recompute(in: context)
        let ascents = try context.fetch(FetchDescriptor<AchievementEvent>())
            .filter { $0.family == .monthlyAscent }
            .sorted { $0.logicalMonth < $1.logicalMonth }

        XCTAssertEqual(ascents.count, 2)
        XCTAssertEqual(ascents.map(\.observedAmount), [25_000, 50_000])
    }

    func testMonthlyAscentDoesNotCompareAcrossGapOrCurrency() throws {
        let context = container.mainContext
        context.insert(snapshot("2026-01-01", total: 100_000, currency: "AUD"))
        context.insert(snapshot("2026-03-01", total: 400_000, currency: "AUD"))
        context.insert(snapshot("2026-04-01", total: 800_000, currency: "CNY"))
        try context.save()

        _ = try AchievementService.recompute(in: context)
        let events = try context.fetch(FetchDescriptor<AchievementEvent>())

        XCTAssertTrue(events.filter { $0.family == .monthlyAscent }.isEmpty)
    }

    func testTimeMarksUseLogicalMonthAndBackfillContiguousHistory() throws {
        let context = container.mainContext
        for month in 1...6 {
            let value = 10_000 + Decimal(month)
            context.insert(snapshot(String(format: "2026-%02d-01", month), total: value, currency: "AUD"))
        }
        try context.save()

        _ = try AchievementService.recompute(in: context)
        let marks = try context.fetch(FetchDescriptor<AchievementEvent>())
            .filter { $0.family == .timeMark }

        XCTAssertEqual(Set(marks.map(\.stageKey)), Set(["time-3", "time-6"]))
    }

    func testCorrectionRemovesInvalidMilestoneButMarketDeclineDoesNot() throws {
        let context = container.mainContext
        let january = snapshot("2026-01-01", total: 1_100_000, currency: "AUD")
        let february = snapshot("2026-02-01", total: 800_000, currency: "AUD")
        context.insert(january)
        context.insert(february)
        try context.save()

        _ = try AchievementService.recompute(in: context)
        XCTAssertNotNil(try event("wealth-3", in: context))

        // A later market decline does not revoke January's factual crossing.
        _ = try AchievementService.recompute(in: context)
        XCTAssertNotNil(try event("wealth-3", in: context))

        // Correcting the qualifying source value does invalidate it.
        january.totalAmount = 900_000
        try context.save()
        let correction = try AchievementService.recompute(in: context)

        XCTAssertNil(try event("wealth-3", in: context))
        XCTAssertGreaterThan(correction.removedCount, 0)
    }

    private func event(_ key: String, in context: ModelContext) throws -> AchievementEvent? {
        let all = try context.fetch(FetchDescriptor<AchievementEvent>())
        return all.first { $0.eventKey == key }
    }

    private func snapshot(_ date: String, total: Decimal, currency: String) -> PortfolioSnapshot {
        PortfolioSnapshot(
            periodMonth: ISO8601DateFormatter().date(from: "\(date)T00:00:00Z")!,
            homeCurrency: currency,
            totalAmount: total,
            entries: [],
            rates: []
        )
    }
}

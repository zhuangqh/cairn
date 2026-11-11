import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class BatchUpsertServiceTests: InMemoryStoreTestCase {
    func testApplyCreatesSnapshotsForEnteredRows() throws {
        let context = container.mainContext
        let holding = insertHolding(in: context)
        try context.save()

        let rows = [BatchUpsertService.Row(holdingId: holding.id, amount: 1_000)]
        try BatchUpsertService.apply(rows, periodMonth: .now, context: context)

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.amount, 1_000)
    }

    func testApplySkipsNilRows() throws {
        let context = container.mainContext
        let account = Account(name: "Primary", kind: .cash)
        let entered = Holding(currency: "USD", account: account)
        let blank = Holding(currency: "EUR", account: account)
        context.insert(account)
        context.insert(entered)
        context.insert(blank)
        try context.save()

        let rows = [
            BatchUpsertService.Row(holdingId: entered.id, amount: 500),
            BatchUpsertService.Row(holdingId: blank.id, amount: nil)
        ]
        try BatchUpsertService.apply(rows, periodMonth: .now, context: context)

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.holding?.currency, "USD")
    }

    func testApplyUpdatesExistingSnapshotForSameMonth() throws {
        let context = container.mainContext
        let holding = insertHolding(in: context)
        try context.save()

        try BatchUpsertService.apply(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 100)],
            periodMonth: .now,
            context: context
        )
        try BatchUpsertService.apply(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 250)],
            periodMonth: .now,
            context: context
        )

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.amount, 250)
    }

    func testReplaceMonthRemovesStaleSnapshotsBeforeWritingCurrentRows() throws {
        let context = container.mainContext
        let holding = insertHolding(in: context)

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let monthStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let laterInMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let nextMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))

        context.insert(Snapshot(periodMonth: monthStart, amount: 100, holding: holding))
        context.insert(Snapshot(periodMonth: laterInMonth, amount: 200, holding: holding))
        context.insert(Snapshot(periodMonth: nextMonth, amount: 300, holding: holding))
        try context.save()

        try BatchUpsertService.replaceMonth(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 500)],
            periodMonth: monthStart,
            context: context
        )

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
            .sorted { $0.periodMonth < $1.periodMonth }
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first?.periodMonth, Snapshot.normalizeDay(monthStart))
        XCTAssertEqual(snapshots.first?.amount, 500)
        XCTAssertEqual(snapshots.last?.periodMonth, Snapshot.normalizeDay(nextMonth))
        XCTAssertEqual(snapshots.last?.amount, 300)
    }

    func testReplaceMonthDeletesExistingRowsForBlankAmounts() throws {
        let context = container.mainContext
        let holding = insertHolding(in: context)

        let month = Snapshot.normalize(.now)
        context.insert(Snapshot(periodMonth: month, amount: 100, holding: holding))
        try context.save()

        try BatchUpsertService.replaceMonth(
            [BatchUpsertService.Row(holdingId: holding.id, amount: nil)],
            periodMonth: month,
            context: context
        )

        let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
        XCTAssertTrue(snapshots.isEmpty)
    }

    // MARK: - saveBatch

    func testSaveBatchWritesHoldingRowsAndCaptureTogether() async throws {
        let context = container.mainContext
        let holding = insertHolding(currency: "EUR", in: context)
        try context.save()
        let day = try date("2026-02-15T00:00:00Z")

        let portfolio = try await BatchUpsertService.saveBatch(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 180)],
            replacingMonth: false,
            periodMonth: day,
            homeCurrency: "USD",
            note: "Feb",
            fetcher: StubFXFetcher(response: FXRateResponse(base: "USD", date: day, rates: ["EUR": 0.9])),
            context: context,
            now: try date("2026-03-01T00:00:00Z")
        )

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snapshot>()).map(\.amount), [180])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).count, 1)
        XCTAssertEqual(portfolio.entries.map(\.amount), [180])
        XCTAssertEqual(portfolio.totalAmount, 200)
        XCTAssertEqual(portfolio.note, "Feb")
    }

    func testSaveBatchReplacingMonthCapturesOnlyReplacementRows() async throws {
        let context = container.mainContext
        let holding = insertHolding(in: context)
        let monthStart = try date("2026-04-01T00:00:00Z")
        context.insert(Snapshot(periodMonth: monthStart, amount: 100, holding: holding))
        context.insert(Snapshot(periodMonth: try date("2026-04-20T00:00:00Z"), amount: 200, holding: holding))
        try context.save()

        let portfolio = try await BatchUpsertService.saveBatch(
            [BatchUpsertService.Row(holdingId: holding.id, amount: 500)],
            replacingMonth: true,
            periodMonth: monthStart,
            homeCurrency: "USD",
            note: nil,
            fetcher: FailingFetcher(),
            context: context,
            now: try date("2026-05-01T00:00:00Z")
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<Snapshot>()).map(\.amount), [500])
        XCTAssertEqual(portfolio.entries.map(\.amount), [500])
        XCTAssertEqual(portfolio.totalAmount, 500)
    }

    /// A capture failure after the holding rows are staged must not leave
    /// them saved without their `PortfolioSnapshot`.
    func testSaveBatchRollsBackHoldingRowsWhenCaptureFails() async throws {
        let context = container.mainContext
        let holding = insertHolding(in: context)
        let day = try date("2026-02-15T00:00:00Z")
        context.insert(Snapshot(periodMonth: day, amount: 100, holding: holding))
        try context.save()

        let fetcher = FailingModelFetcher(context: context, failingType: PortfolioSnapshot.self)
        do {
            try await BatchUpsertService.saveBatch(
                [BatchUpsertService.Row(holdingId: holding.id, amount: 999)],
                replacingMonth: false,
                periodMonth: day,
                homeCurrency: "USD",
                note: nil,
                fetcher: FailingFetcher(),
                context: context,
                fetching: fetcher
            )
            XCTFail("Expected saveBatch to throw")
        } catch {}

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snapshot>()).map(\.amount), [100])
        XCTAssertTrue(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).isEmpty)
    }

    func testSaveBatchReplacingMonthRestoresDeletedRowsWhenCaptureFails() async throws {
        let context = container.mainContext
        let holding = insertHolding(in: context)
        let monthStart = try date("2026-04-01T00:00:00Z")
        context.insert(Snapshot(periodMonth: monthStart, amount: 100, holding: holding))
        context.insert(Snapshot(periodMonth: try date("2026-04-20T00:00:00Z"), amount: 200, holding: holding))
        try context.save()

        let fetcher = FailingModelFetcher(context: context, failingType: PortfolioSnapshot.self)
        do {
            try await BatchUpsertService.saveBatch(
                [BatchUpsertService.Row(holdingId: holding.id, amount: 500)],
                replacingMonth: true,
                periodMonth: monthStart,
                homeCurrency: "USD",
                note: nil,
                fetcher: FailingFetcher(),
                context: context,
                fetching: fetcher
            )
            XCTFail("Expected saveBatch to throw")
        } catch {}

        let amounts = try context.fetch(FetchDescriptor<Snapshot>()).map(\.amount).sorted()
        XCTAssertEqual(amounts, [100, 200])
        XCTAssertTrue(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).isEmpty)
    }
}

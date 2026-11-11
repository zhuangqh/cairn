import XCTest
import SwiftData
@testable import Cairn

@MainActor
final class BackupServiceCSVTests: InMemoryStoreTestCase {
    func testSnapshotCSVExportsBatchRowsInNativeCurrencies() throws {
        let context = container.mainContext
        let alice = Member(name: "Alice")
        let cash = Account(name: "Cash", kind: .cash, member: alice)
        let cnyHolding = Holding(currency: "CNY", label: "Everyday", account: cash)
        let bob = Member(name: "Bob")
        let broker = Account(name: "Broker, AU", kind: .stock, member: bob)
        let usdHolding = Holding(currency: "USD", account: broker)
        context.insert(alice)
        context.insert(cash)
        context.insert(cnyHolding)
        context.insert(bob)
        context.insert(broker)
        context.insert(usdHolding)
        context.insert(Snapshot(periodMonth: try date("2026-02-15T00:00:00Z"), amount: 500, holding: cnyHolding))
        context.insert(Snapshot(periodMonth: try date("2026-02-15T00:00:00Z"), amount: 12.34, holding: usdHolding))
        context.insert(Snapshot(periodMonth: try date("2026-03-20T00:00:00Z"), amount: 750, holding: cnyHolding))

        let first = try batchPortfolio(cnyHolding: cnyHolding, usdHolding: usdHolding)
        let second = PortfolioSnapshot(
            periodMonth: try date("2026-03-01T00:00:00Z"),
            homeCurrency: "AUD",
            totalAmount: 1_500,
            entries: [
                PortfolioSnapshot.Entry(
                    holdingId: cnyHolding.id,
                    memberName: "Alice",
                    accountName: "Cash",
                    holdingLabel: "Everyday",
                    currency: "CNY",
                    amount: 750,
                    convertedAmount: 150
                )
            ],
            rates: [
                PortfolioSnapshot.Rate(base: "AUD", quote: "CNY", rate: 4.90)
            ],
            recordedAt: try date("2026-03-02T03:04:05Z")
        )
        context.insert(second)
        context.insert(first)
        try context.save()

        let csv = try XCTUnwrap(String(bytes: try BackupService.makeSnapshotCSV(in: context), encoding: .utf8))

        XCTAssertEqual(
            csv,
            """
            date,period,recordedAt,homeCurrency,totalAmount,note,rateDate,rate CNY->AUD,rate USD->AUD,Alice / Cash / Everyday (CNY),"Bob / Broker, AU (USD)"
            2026-02-15,2026-02-01,2026-02-02T03:04:05Z,AUD,999,"first, batch",2026-02-15,0.21,1.52,500,12.34
            2026-03-20,2026-03-01,2026-03-02T03:04:05Z,AUD,1500,,2026-03-20,0.20,,750,

            """
        )
        XCTAssertFalse(csv.contains(",100,"))
        XCTAssertFalse(csv.contains(",150\n"))
    }

    func testSnapshotCSVKeepsDirectForeignToHomeRates() throws {
        let context = container.mainContext
        let portfolio = PortfolioSnapshot(
            periodMonth: try date("2026-02-01T00:00:00Z"),
            homeCurrency: "AUD",
            totalAmount: 100,
            entries: [],
            rates: [
                PortfolioSnapshot.Rate(base: "USD", quote: "AUD", rate: 1.52)
            ],
            recordedAt: try date("2026-02-02T03:04:05Z")
        )
        context.insert(portfolio)
        try context.save()

        let csv = try XCTUnwrap(String(bytes: try BackupService.makeSnapshotCSV(in: context), encoding: .utf8))

        XCTAssertEqual(
            csv,
            """
            date,period,recordedAt,homeCurrency,totalAmount,note,rateDate,rate USD->AUD
            2026-02-01,2026-02-01,2026-02-02T03:04:05Z,AUD,100,,2026-02-01,1.52

            """
        )
    }

    /// February batch capturing both holdings, with converted amounts and
    /// home-quoted rates that the native-currency CSV must not leak.
    private func batchPortfolio(cnyHolding: Holding, usdHolding: Holding) throws -> PortfolioSnapshot {
        PortfolioSnapshot(
            periodMonth: try date("2026-02-01T00:00:00Z"),
            homeCurrency: "AUD",
            totalAmount: 999,
            entries: [
                PortfolioSnapshot.Entry(
                    holdingId: usdHolding.id,
                    memberName: "Bob",
                    accountName: "Broker, AU",
                    holdingLabel: nil,
                    currency: "USD",
                    amount: 12.34,
                    convertedAmount: 99
                ),
                PortfolioSnapshot.Entry(
                    holdingId: cnyHolding.id,
                    memberName: "Alice",
                    accountName: "Cash",
                    holdingLabel: "Everyday",
                    currency: "CNY",
                    amount: 500,
                    convertedAmount: 100
                )
            ],
            rates: [
                PortfolioSnapshot.Rate(base: "AUD", quote: "CNY", rate: 4.75),
                PortfolioSnapshot.Rate(base: "AUD", quote: "USD", rate: 0.66)
            ],
            note: "first, batch",
            recordedAt: try date("2026-02-02T03:04:05Z")
        )
    }
}

import XCTest
import SwiftData
@testable import Cairn

/// Base class for tests that need a fresh in-memory store per test.
@MainActor
class InMemoryStoreTestCase: XCTestCase {
    var container: ModelContainer!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(.inMemory)
    }

    override func tearDown() async throws {
        container = nil
    }
}

extension XCTestCase {
    /// Parses an ISO 8601 timestamp such as `2026-02-15T00:00:00Z`.
    func date(_ iso8601: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso8601))
    }
}

/// Inserts an optional member, a cash account, and one holding, in that order.
@MainActor
@discardableResult
func insertHolding(
    currency: String = "USD",
    accountName: String = "Primary",
    memberName: String? = nil,
    in context: ModelContext
) -> Holding {
    let member = memberName.map { Member(name: $0) }
    let account = Account(name: accountName, kind: .cash, member: member)
    let holding = Holding(currency: currency, account: account)
    if let member {
        context.insert(member)
    }
    context.insert(account)
    context.insert(holding)
    return holding
}

// MARK: - FX fetcher stubs

/// Returns a fixed response for every latest-rate request.
struct StubFXFetcher: FXRateFetching {
    let response: FXRateResponse

    func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse {
        response
    }
}

/// Simulates an offline network for every request.
struct FailingFetcher: FXRateFetching {
    func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse {
        throw URLError(.notConnectedToInternet)
    }
}

/// Answers only historical requests for `expectedDate`; everything else throws.
struct ExactDateFetcher: FXRateFetching {
    let expectedDate: Date
    let response: FXRateResponse

    func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse {
        throw NSError(domain: "ExactDateFetcher", code: 1)
    }

    func fetch(base: String, quotes: [String], on date: Date) async throws -> FXRateResponse {
        guard date == expectedDate else {
            throw NSError(domain: "ExactDateFetcher", code: 2)
        }
        return response
    }
}

// MARK: - Model fetch stubs

/// Forwards fetches to `context` but throws for one model type, simulating a
/// store read failure partway through a multi-model operation.
struct FailingModelFetcher: ModelFetching {
    let context: ModelContext
    let failingType: any PersistentModel.Type

    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        if ObjectIdentifier(T.self) == ObjectIdentifier(failingType) {
            throw NSError(domain: "FailingModelFetcher", code: 1)
        }
        return try context.fetch(descriptor)
    }
}

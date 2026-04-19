import Foundation
import SwiftData

/// Abstraction over the network fetch so tests can inject a stub.
public protocol FXRateFetching: Sendable {
    /// Returns rates keyed by quote currency: `1 unit of base == rate × quote`.
    func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse

    /// Returns rates keyed by quote currency for a specific historical
    /// date. Implementations should return the closest available
    /// business-day rate when the exact date has no quote.
    func fetch(base: String, quotes: [String], on date: Date) async throws -> FXRateResponse
}

public extension FXRateFetching {
    /// Default: fall back to `fetchLatest` for fetchers that don't care
    /// about dates (e.g. test stubs).
    func fetch(base: String, quotes: [String], on date: Date) async throws -> FXRateResponse {
        try await fetchLatest(base: base, quotes: quotes)
    }
}

public struct FXRateResponse: Sendable {
    public let base: String
    public let date: Date
    public let rates: [String: Decimal]

    public init(base: String, date: Date, rates: [String: Decimal]) {
        self.base = base
        self.date = date
        self.rates = rates
    }
}

/// Default fetcher backed by the free [Frankfurter](https://frankfurter.dev) API.
/// Used only at refresh time; the rest of the app reads cached `FXRate` rows.
public struct FrankfurterFetcher: FXRateFetching {
    public init() {}

    public func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse {
        try await fetch(base: base, quotes: quotes, endpoint: "latest")
    }

    public func fetch(base: String, quotes: [String], on date: Date) async throws -> FXRateResponse {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        let endpoint = formatter.string(from: date)
        return try await fetch(base: base, quotes: quotes, endpoint: endpoint)
    }

    private func fetch(base: String, quotes: [String], endpoint: String) async throws -> FXRateResponse {
        let filtered = quotes.filter { $0 != base }
        guard !filtered.isEmpty else {
            return FXRateResponse(base: base, date: .now, rates: [:])
        }
        // Use the canonical `frankfurter.dev/v1` host directly. The legacy
        // `api.frankfurter.app/latest` endpoint now returns a 301 redirect to
        // this URL, and relying on implicit redirect following across hosts
        // has caused intermittent fetch failures in release builds.
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/\(endpoint)")
        components?.queryItems = [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "symbols", value: filtered.joined(separator: ","))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[FX] \(url.absoluteString) -> HTTP \(http.statusCode): \(body)")
            #endif
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(formatter)

        let payload = try decoder.decode(FrankfurterPayload.self, from: data)
        let rates = payload.rates.mapValues { Decimal($0) }
        return FXRateResponse(base: payload.base, date: payload.date, rates: rates)
    }

    private struct FrankfurterPayload: Decodable {
        let base: String
        let date: Date
        let rates: [String: Double]
    }
}

/// FX cache + conversion helpers built on top of the `FXRate` SwiftData model.
@MainActor
public enum FXService {
    /// Refreshes the cache for `base -> quotes` using `fetcher` and persists the
    /// results as `FXRate` rows. An existing row with the same `(base, quote)`
    /// is updated in place.
    @discardableResult
    public static func refresh(
        base: String,
        quotes: [String],
        fetcher: any FXRateFetching = FrankfurterFetcher(),
        context: ModelContext
    ) async throws -> [FXRate] {
        let response = try await fetcher.fetchLatest(base: base, quotes: quotes)
        var stored: [FXRate] = []
        for (quote, rate) in response.rates {
            let existing = fetchRate(base: base, quote: quote, in: context)
            if let existing {
                existing.rate = rate
                existing.date = response.date
                stored.append(existing)
            } else {
                let row = FXRate(base: base, quote: quote, rate: rate, date: response.date)
                context.insert(row)
                stored.append(row)
            }
        }
        try context.save()
        return stored
    }

    /// Latest cached rate for the pair, or `nil` if not yet fetched.
    public static func latestRate(base: String, quote: String, in context: ModelContext) -> FXRate? {
        if base == quote {
            return nil // caller handles identity conversion
        }
        return fetchRate(base: base, quote: quote, in: context)
    }

    /// Converts `amount` from `from` to `to` using cached rates.
    /// Returns `nil` if no rate is available and the currencies differ.
    public static func convert(
        amount: Decimal,
        from: String,
        to: String,
        in context: ModelContext
    ) -> Decimal? {
        if from == to { return amount }
        if let direct = fetchRate(base: from, quote: to, in: context) {
            return amount * direct.rate
        }
        // Try the inverse pair.
        if let inverse = fetchRate(base: to, quote: from, in: context), inverse.rate != 0 {
            return amount / inverse.rate
        }
        return nil
    }

    /// In-memory snapshot of every cached `FXRate` row, keyed by
    /// `(base, quote)`. Built once via `RateCache.load(in:)` and reused for
    /// every `convert(...)` call within an aggregation pass — replaces the
    /// per-conversion SwiftData `#Predicate` fetch which is the dominant
    /// hotspot when computing trends across many holdings × months.
    public struct RateCache: Sendable {
        // [base: [quote: rate]]
        @usableFromInline var pairs: [String: [String: Decimal]]

        @usableFromInline init(pairs: [String: [String: Decimal]]) {
            self.pairs = pairs
        }

        public static let empty = RateCache(pairs: [:])

        /// Eagerly load every `FXRate` from `context` into a memory map.
        public static func load(in context: ModelContext) -> RateCache {
            let rows = (try? context.fetch(FetchDescriptor<FXRate>())) ?? []
            var pairs: [String: [String: Decimal]] = [:]
            for row in rows {
                pairs[row.base, default: [:]][row.quote] = row.rate
            }
            return RateCache(pairs: pairs)
        }

        @inlinable
        public func rate(from base: String, to quote: String) -> Decimal? {
            pairs[base]?[quote]
        }

        /// Convert with the same fallback rules as `FXService.convert`,
        /// but purely in-memory.
        @inlinable
        public func convert(amount: Decimal, from: String, to: String) -> Decimal? {
            if from == to { return amount }
            if let direct = pairs[from]?[to] {
                return amount * direct
            }
            if let inverse = pairs[to]?[from], inverse != 0 {
                return amount / inverse
            }
            return nil
        }
    }

    /// Convenience overload that goes through a precomputed `RateCache`,
    /// avoiding per-conversion SwiftData fetches. Prefer this in tight
    /// loops (aggregation, trends).
    @inlinable
    public static func convert(
        amount: Decimal,
        from: String,
        to: String,
        cache: RateCache
    ) -> Decimal? {
        cache.convert(amount: amount, from: from, to: to)
    }

    private static func fetchRate(base: String, quote: String, in context: ModelContext) -> FXRate? {
        // Bind to locals with distinct names so the `#Predicate` closure does
        // not capture identifiers that collide with `FXRate.base` / `.quote`.
        // SwiftData's predicate translation can silently mis-match when a
        // captured value shadows a model property name.
        let baseCode = base
        let quoteCode = quote
        var descriptor = FetchDescriptor<FXRate>(
            predicate: #Predicate { $0.base == baseCode && $0.quote == quoteCode }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

import Foundation
import SwiftData

/// Abstraction over the network fetch so tests can inject a stub.
public protocol FXRateFetching: Sendable {
    /// Returns rates keyed by quote currency: `1 unit of base == rate × quote`.
    func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse
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

/// Default fetcher backed by the free [Frankfurter](https://www.frankfurter.app) API.
/// Used only at refresh time; the rest of the app reads cached `FXRate` rows.
public struct FrankfurterFetcher: FXRateFetching {
    public init() {}

    public func fetchLatest(base: String, quotes: [String]) async throws -> FXRateResponse {
        let filtered = quotes.filter { $0 != base }
        guard !filtered.isEmpty else {
            return FXRateResponse(base: base, date: .now, rates: [:])
        }
        var components = URLComponents(string: "https://api.frankfurter.app/latest")
        components?.queryItems = [
            URLQueryItem(name: "from", value: base),
            URLQueryItem(name: "to", value: filtered.joined(separator: ","))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
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

    private static func fetchRate(base: String, quote: String, in context: ModelContext) -> FXRate? {
        var descriptor = FetchDescriptor<FXRate>(
            predicate: #Predicate { $0.base == base && $0.quote == quote }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

import Foundation
import SwiftData

// MARK: - Historical FX rates + note loading for BatchEntryView
//
// These helpers power the rates chips and note prefill shown in the
// batch-entry sheet. Kept in a standalone file so the main view stays
// within lint limits.

extension BatchEntryView {
    /// Identity for the rates/note load task; changing either input
    /// restarts it.
    struct RatesKey: Equatable {
        let periodMonth: Date
        let homeCurrency: String
    }

    /// Distinct non-home currencies currently in use across active
    /// holdings, sorted for stable display. Empty when everything is
    /// already denominated in `homeCurrency`.
    var neededQuoteCurrencies: [String] {
        neededQuoteCurrencies(rows: groupedRows.flatMap(\.rows))
    }

    func neededQuoteCurrencies(rows: [HoldingRow]) -> [String] {
        var seen: Set<String> = []
        for row in rows where row.holding.currency != homeCurrency {
            seen.insert(row.holding.currency)
        }
        return seen.sorted()
    }

    /// Fetches month-appropriate FX rates and stores them in view state.
    /// Uses the last day of `periodMonth` as the reference date (or
    /// "now" for the current/future month) so historical chips reflect
    /// the closing rate for that period.
    @MainActor
    func loadHistoricalRates() async {
        // When editing a captured snapshot, FX rates are locked to the
        // values stored on the snapshot — never refetch.
        if let lockedRates {
            historicalRates = lockedRates
            historicalRatesAsOf = nil
            ratesFetchError = nil
            isLoadingRates = false
            return
        }
        let quotes = neededQuoteCurrencies
        guard !quotes.isEmpty else {
            historicalRates = [:]
            historicalRatesAsOf = nil
            ratesFetchError = nil
            isLoadingRates = false
            return
        }

        isLoadingRates = true
        ratesFetchError = nil
        // A cancelled load leaves the flag to its replacement task.
        defer { if !Task.isCancelled { isLoadingRates = false } }

        let referenceDate = Self.referenceDate(for: periodMonth, now: .now)
        do {
            let response = try await ratesFetcher.fetch(
                base: homeCurrency,
                quotes: quotes,
                on: referenceDate
            )
            guard !Task.isCancelled else { return }
            historicalRates = response.rates
            historicalRatesAsOf = response.date
        } catch {
            guard !Task.isCancelled else { return }
            historicalRates = [:]
            historicalRatesAsOf = nil
            ratesFetchError = error.localizedDescription
        }
    }

    /// Hydrates `note` from any existing `PortfolioSnapshot` for the
    /// current `(periodMonth, homeCurrency)`. Clears the field when no
    /// snapshot exists so switching months doesn't leak text between
    /// periods.
    @MainActor
    func loadNoteForCurrentMonth() {
        if isMonthLocked {
            originalNote = initialNote ?? note
            return
        }
        let normalized = Snapshot.normalize(periodMonth)
        let currency = homeCurrency
        var descriptor = FetchDescriptor<PortfolioSnapshot>(
            predicate: #Predicate { $0.periodMonth == normalized && $0.homeCurrency == currency }
        )
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor))?.first
        note = existing?.note ?? ""
        originalNote = note
    }

    /// Day-granular reference date for FX lookups: use the exact day the
    /// user picked, capped at `now` for future dates because the
    /// Frankfurter provider has no forward rates. Historical days return
    /// the closest available business-day rate (the provider handles
    /// weekends/holidays server-side).
    private static func referenceDate(for periodMonth: Date, now: Date) -> Date {
        let picked = Snapshot.normalizeDay(periodMonth)
        return min(picked, now)
    }
}

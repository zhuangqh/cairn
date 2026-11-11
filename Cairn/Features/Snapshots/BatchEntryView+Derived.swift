import SwiftUI
import SwiftData

// MARK: - Derived data + actions for BatchEntryView
//
// Extracted to a separate file purely to keep the main view's type body
// small; everything here is conceptually part of `BatchEntryView`.

extension BatchEntryView {
    struct HoldingRow {
        let holding: Holding
        let savedAmount: Decimal?
        let previousAmount: Decimal?
    }

    struct MemberGroup {
        let member: Member
        let rows: [HoldingRow]
    }

    var groupedRows: [MemberGroup] {
        members.compactMap { member in
            let accounts = member.accounts ?? []
            let holdings = accounts
                .flatMap { $0.holdings ?? [] }
                .filter { $0.isArchived == false }
                .sorted { lhs, rhs in
                    let lhsName = lhs.account?.name ?? ""
                    let rhsName = rhs.account?.name ?? ""
                    if lhsName == rhsName { return lhs.currency < rhs.currency }
                    return lhsName < rhsName
                }
            guard !holdings.isEmpty else { return nil }

            let rows = holdings.map { holding in
                let amounts = amounts(for: holding, at: periodMonth)
                return HoldingRow(
                    holding: holding,
                    savedAmount: lockedBaseline?[holding.id] ?? amounts.saved,
                    previousAmount: amounts.previous
                )
            }
            return MemberGroup(member: member, rows: rows)
        }
    }

    func amounts(for holding: Holding, at month: Date) -> (saved: Decimal?, previous: Decimal?) {
        var saved: Decimal?
        var latestPriorDate: Date?
        var latestPriorAmount: Decimal?
        for snapshot in holding.snapshots ?? [] {
            if snapshot.periodMonth == month {
                saved = snapshot.amount
            } else if snapshot.periodMonth < month,
                      latestPriorDate.map({ snapshot.periodMonth > $0 }) ?? true {
                latestPriorDate = snapshot.periodMonth
                latestPriorAmount = snapshot.amount
            }
        }
        return (saved, latestPriorAmount)
    }

    func binding(for row: HoldingRow) -> Binding<Decimal?> {
        let holdingId = row.holding.id
        let savedAmount = row.savedAmount
        return Binding(
            get: { edits[holdingId] ?? savedAmount },
            set: { newValue in edits[holdingId] = newValue }
        )
    }

    func currentSavedAmount(for holdingId: UUID, in rows: [HoldingRow]) -> Decimal? {
        rows.first { $0.holding.id == holdingId }?.savedAmount
    }

    func currentAmount(for row: HoldingRow) -> Decimal? {
        let holdingId = row.holding.id
        if let staged = edits[holdingId] { return staged }
        return row.savedAmount
    }

    /// Converts `amount` (in `from`) to the home currency using the same
    /// rate source the UI displays. Prefers the day-specific historical
    /// rate fetched for `periodMonth` so the chips and the totals always
    /// agree; falls back to the local `FXRate` cache when the live fetch
    /// produced nothing (offline / no rate for that day).
    ///
    /// `cache` is the pass's in-memory copy of the `FXRate` rows; it applies
    /// the same direct-then-inverse lookup as `FXService.convert(in:)`
    /// without a `#Predicate` fetch per row.
    func convertToHome(amount: Decimal, from currency: String, cache: FXService.RateCache) -> Decimal? {
        FXService.convert(
            amount: amount,
            from: currency,
            to: homeCurrency,
            historicalRates: historicalRates
        ) {
            cache.convert(amount: amount, from: currency, to: homeCurrency)
        }
    }

    /// Rows and conversion inputs derived once per render pass, so each
    /// keystroke rebuilds `groupedRows` and loads the rate cache once
    /// rather than once per consumer.
    struct DerivedPass {
        let groups: [MemberGroup]
        let rows: [HoldingRow]
        let rateCache: FXService.RateCache
    }

    func derivePass() -> DerivedPass {
        let groups = groupedRows
        let rows = groups.flatMap(\.rows)
        // The cached `FXRate` rows are only consulted for currencies the
        // fetched historical rates don't cover.
        let needsCache = rows.contains { row in
            row.holding.currency != homeCurrency && (historicalRates[row.holding.currency] ?? 0) == 0
        }
        return DerivedPass(
            groups: groups,
            rows: rows,
            rateCache: needsCache ? FXService.RateCache.load(in: context) : .empty
        )
    }

    func approxHome(for row: HoldingRow, cache: FXService.RateCache) -> Decimal? {
        guard let amount = currentAmount(for: row) else { return nil }
        return convertToHome(amount: amount, from: row.holding.currency, cache: cache)
    }

    func totalInHome(_ pass: DerivedPass) -> Decimal {
        pass.rows.reduce(Decimal(0)) { running, row in
            guard let converted = approxHome(for: row, cache: pass.rateCache) else { return running }
            return running + converted
        }
    }

    func unresolvedCurrencies(_ pass: DerivedPass) -> [String] {
        var codes: Set<String> = []
        for row in pass.rows {
            guard let amount = currentAmount(for: row), amount != 0 else { continue }
            if row.holding.currency == homeCurrency { continue }
            if convertToHome(amount: amount, from: row.holding.currency, cache: pass.rateCache) == nil {
                codes.insert(row.holding.currency)
            }
        }
        return codes.sorted()
    }

    func hasUnsavedEdits(rows: [HoldingRow]) -> Bool {
        if note != originalNote { return true }
        return edits.contains { key, value in
            value != currentSavedAmount(for: key, in: rows)
        }
    }

    func hasBlankWithPrevious(rows: [HoldingRow]) -> Bool {
        rows.contains { row in
            currentAmount(for: row) == nil && row.previousAmount != nil
        }
    }

    // MARK: - Actions

    func fillFromLast() {
        for row in groupedRows.flatMap(\.rows) {
            let current = currentAmount(for: row)
            if current == nil, let last = row.previousAmount {
                edits[row.holding.id] = last
            }
        }
    }

    func clearAll() {
        for row in groupedRows.flatMap(\.rows) {
            edits[row.holding.id] = Optional<Decimal>.none
        }
    }

}

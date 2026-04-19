import SwiftUI
import SwiftData

// MARK: - Derived data + actions for BatchEntryView
//
// Extracted to a separate file purely to keep the main view's type body
// small; everything here is conceptually part of `BatchEntryView`.

extension BatchEntryView {
    struct HoldingRow {
        let holding: Holding
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
                HoldingRow(
                    holding: holding,
                    previousAmount: latestPriorAmount(for: holding, before: periodMonth)
                )
            }
            return MemberGroup(member: member, rows: rows)
        }
    }

    func latestPriorAmount(for holding: Holding, before month: Date) -> Decimal? {
        (holding.snapshots ?? [])
            .filter { $0.periodMonth < month }
            .sorted { $0.periodMonth > $1.periodMonth }
            .first?.amount
    }

    func snapshot(for holding: Holding, periodMonth: Date) -> Snapshot? {
        (holding.snapshots ?? []).first { $0.periodMonth == periodMonth }
    }

    func binding(for holdingId: UUID) -> Binding<Decimal?> {
        Binding(
            get: { edits[holdingId] ?? currentSavedAmount(for: holdingId) },
            set: { newValue in edits[holdingId] = newValue }
        )
    }

    func currentSavedAmount(for holdingId: UUID) -> Decimal? {
        if let lockedBaseline, let value = lockedBaseline[holdingId] {
            return value
        }
        let rows = groupedRows.flatMap(\.rows)
        guard let holding = rows.first(where: { $0.holding.id == holdingId })?.holding else { return nil }
        return snapshot(for: holding, periodMonth: periodMonth)?.amount
    }

    func currentAmount(for holdingId: UUID) -> Decimal? {
        if let staged = edits[holdingId] { return staged }
        return currentSavedAmount(for: holdingId)
    }

    /// Converts `amount` (in `from`) to the home currency using the same
    /// rate source the UI displays. Prefers the day-specific historical
    /// rate fetched for `periodMonth` so the chips and the totals always
    /// agree; falls back to the local `FXRate` cache when the live fetch
    /// produced nothing (offline / no rate for that day).
    ///
    /// `historicalRates[foreign]` follows the Frankfurter convention
    /// `1 home = rate × foreign`, i.e. units `foreign / home`, so the
    /// home-side amount is `foreignAmount / rate`.
    func convertToHome(amount: Decimal, from currency: String) -> Decimal? {
        if currency == homeCurrency { return amount }
        if let rate = historicalRates[currency], rate != 0 {
            return amount / rate
        }
        return FXService.convert(
            amount: amount,
            from: currency,
            to: homeCurrency,
            in: context
        )
    }

    func approxHome(for row: HoldingRow) -> Decimal? {
        guard let amount = currentAmount(for: row.holding.id) else { return nil }
        return convertToHome(amount: amount, from: row.holding.currency)
    }

    var totalInHome: Decimal {
        groupedRows.flatMap(\.rows).reduce(Decimal(0)) { running, row in
            guard let converted = approxHome(for: row) else { return running }
            return running + converted
        }
    }

    var unresolvedCurrencies: [String] {
        var codes: Set<String> = []
        for row in groupedRows.flatMap(\.rows) {
            guard let amount = currentAmount(for: row.holding.id), amount != 0 else { continue }
            if row.holding.currency == homeCurrency { continue }
            if convertToHome(amount: amount, from: row.holding.currency) == nil {
                codes.insert(row.holding.currency)
            }
        }
        return codes.sorted()
    }

    var unresolvedFootnote: String {
        let template = String(localized: "overview.missingRates")
        return template.replacingOccurrences(of: "{currencies}", with: unresolvedCurrencies.joined(separator: ", "))
    }

    var hasUnsavedEdits: Bool {
        if note != originalNote { return true }
        return edits.contains { key, value in
            value != currentSavedAmount(for: key)
        }
    }

    var filledSummary: String {
        let rows = groupedRows.flatMap(\.rows)
        let total = rows.count
        let filled = rows.filter { currentAmount(for: $0.holding.id) != nil }.count
        return "\(filled) / \(total)"
    }

    var hasBlankWithPrevious: Bool {
        groupedRows.flatMap(\.rows).contains { row in
            currentAmount(for: row.holding.id) == nil && row.previousAmount != nil
        }
    }

    // MARK: - Actions

    func fillFromLast() {
        for row in groupedRows.flatMap(\.rows) {
            let current = currentAmount(for: row.holding.id)
            if current == nil, let last = row.previousAmount {
                edits[row.holding.id] = last
            }
        }
    }

    /// Seeds `edits` from the latest prior snapshot on first appearance.
    /// Runs only when there's nothing staged / saved for the current
    /// month yet, so re-opening after a partial save doesn't clobber
    /// the user's work.
    func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        for row in groupedRows.flatMap(\.rows) where currentAmount(for: row.holding.id) == nil {
            if let previous = row.previousAmount {
                edits[row.holding.id] = previous
            }
        }
    }

    func clearAll() {
        for row in groupedRows.flatMap(\.rows) {
            edits[row.holding.id] = Optional<Decimal>.none
        }
    }

    func formatAmount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}

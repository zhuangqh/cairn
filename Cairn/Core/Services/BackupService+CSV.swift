import Foundation
import SwiftData

// MARK: - Snapshot CSV export

extension BackupService {
    /// Exports captured batch snapshots as a wide CSV table. Each row is one
    /// `PortfolioSnapshot`; holding columns are ordered by member, account,
    /// label, then currency, and values remain in each holding's native
    /// currency instead of using `convertedAmount`.
    static func makeSnapshotCSV(in context: ModelContext) throws -> Data {
        let snapshots = ((try? context.fetch(FetchDescriptor<PortfolioSnapshot>())) ?? [])
            .sorted { lhs, rhs in
                if lhs.periodMonth == rhs.periodMonth {
                    return lhs.recordedAt < rhs.recordedAt
                }
                return lhs.periodMonth < rhs.periodMonth
            }
        let holdingSnapshots = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []
        // Decode each snapshot's JSON blobs once; both passes below read them.
        let decoded = snapshots.map { (snapshot: $0, entries: $0.entries, rates: $0.rates) }

        var columnsByKey: [CSVColumn.Key: CSVColumn] = [:]
        var rateColumnsByKey: [CSVRateColumn.Key: CSVRateColumn] = [:]
        for (snapshot, entries, rates) in decoded {
            for entry in entries {
                let key = CSVColumn.Key(entry: entry)
                columnsByKey[key] = columnsByKey[key]?.merged(with: entry) ?? CSVColumn(key: key, entry: entry)
            }
            for rate in rates {
                guard let key = CSVRateColumn.Key(rate: rate, homeCurrency: snapshot.homeCurrency) else { continue }
                rateColumnsByKey[key] = CSVRateColumn(key: key)
            }
        }

        let columns = columnsByKey.values.sorted()
        let rateColumns = rateColumnsByKey.values.sorted()
        let header = ["date", "period", "recordedAt", "homeCurrency", "totalAmount", "note", "rateDate"]
            + rateColumns.map(\.header)
            + columns.map(\.header)
        var rows: [[String]] = [header]

        for (snapshot, entries, rates) in decoded {
            let date = PortfolioSnapshotService.capturedDate(for: snapshot, holdingSnapshots: holdingSnapshots)
            let rateByKey = Dictionary(
                rates.compactMap { rate -> (CSVRateColumn.Key, String)? in
                    guard let key = CSVRateColumn.Key(rate: rate, homeCurrency: snapshot.homeCurrency),
                          let exportRate = foreignToHomeRate(rate, homeCurrency: snapshot.homeCurrency)
                    else { return nil }
                    return (key, rateDecimalString(exportRate))
                },
                uniquingKeysWith: { first, _ in first }
            )
            let amountByKey = Dictionary(
                entries.map { (CSVColumn.Key(entry: $0), decimalString($0.amount)) },
                uniquingKeysWith: { first, _ in first }
            )
            rows.append(
                [
                    csvDateFormatter.string(from: date),
                    csvDateFormatter.string(from: snapshot.periodMonth),
                    csvDateTimeFormatter.string(from: snapshot.recordedAt),
                    snapshot.homeCurrency,
                    decimalString(snapshot.totalAmount),
                    snapshot.note ?? "",
                    csvDateFormatter.string(from: date)
                ] + rateColumns.map { rateByKey[$0.key] ?? "" }
                    + columns.map { amountByKey[$0.key] ?? "" }
            )
        }

        let csv = rows
            .map { $0.map(escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n")
            + "\n"
        return Data(csv.utf8)
    }

    private static func foreignToHomeRate(_ rate: PortfolioSnapshot.Rate, homeCurrency: String) -> Decimal? {
        if rate.base == homeCurrency, rate.quote != homeCurrency {
            guard rate.rate != 0 else { return nil }
            return 1 / rate.rate
        }
        if rate.quote == homeCurrency, rate.base != homeCurrency {
            return rate.rate
        }
        return nil
    }

    // Built once and reused: export formats every snapshot's dates and
    // rates, and the configuration never changes.
    private static let csvDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let csvDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static let csvRateFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func rateDecimalString(_ value: Decimal) -> String {
        csvRateFormatter.string(from: NSDecimalNumber(decimal: value)) ?? decimalString(value)
    }

    private static func escapeCSVField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

// Column descriptors live at file scope so their `Key` types stay one level deep.
private struct CSVColumn: Comparable {
    struct Key: Hashable {
        let holdingId: UUID?
        let memberName: String
        let accountName: String
        let holdingLabel: String?
        let currency: String

        init(entry: PortfolioSnapshot.Entry) {
            self.holdingId = entry.holdingId
            self.memberName = entry.memberName
            self.accountName = entry.accountName
            self.holdingLabel = entry.holdingLabel
            self.currency = entry.currency
        }
    }

    let key: Key
    var memberName: String
    var accountName: String
    var holdingLabel: String?
    var currency: String

    init(key: Key, entry: PortfolioSnapshot.Entry) {
        self.key = key
        self.memberName = entry.memberName
        self.accountName = entry.accountName
        self.holdingLabel = entry.holdingLabel
        self.currency = entry.currency
    }

    var header: String {
        let name = [memberName, accountName, holdingLabel ?? ""]
            .compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " / ")
        if name.isEmpty { return currency }
        return "\(name) (\(currency))"
    }

    func merged(with entry: PortfolioSnapshot.Entry) -> CSVColumn {
        CSVColumn(key: key, entry: entry)
    }

    static func < (lhs: CSVColumn, rhs: CSVColumn) -> Bool {
        let lhsValues = [
            lhs.memberName,
            lhs.accountName,
            lhs.holdingLabel ?? "",
            lhs.currency
        ]
        let rhsValues = [
            rhs.memberName,
            rhs.accountName,
            rhs.holdingLabel ?? "",
            rhs.currency
        ]
        if lhsValues == rhsValues {
            return (lhs.key.holdingId?.uuidString ?? "") < (rhs.key.holdingId?.uuidString ?? "")
        }
        return lhsValues.lexicographicallyPrecedes(rhsValues)
    }
}

private struct CSVRateColumn: Comparable {
    struct Key: Hashable {
        let foreignCurrency: String
        let homeCurrency: String

        init?(rate: PortfolioSnapshot.Rate, homeCurrency: String) {
            if rate.base == homeCurrency, rate.quote != homeCurrency {
                self.foreignCurrency = rate.quote
                self.homeCurrency = homeCurrency
            } else if rate.quote == homeCurrency, rate.base != homeCurrency {
                self.foreignCurrency = rate.base
                self.homeCurrency = homeCurrency
            } else {
                return nil
            }
        }
    }

    let key: Key

    var header: String {
        "rate \(key.foreignCurrency)->\(key.homeCurrency)"
    }

    static func < (lhs: CSVRateColumn, rhs: CSVRateColumn) -> Bool {
        if lhs.key.foreignCurrency == rhs.key.foreignCurrency {
            return lhs.key.homeCurrency < rhs.key.homeCurrency
        }
        return lhs.key.foreignCurrency < rhs.key.foreignCurrency
    }
}

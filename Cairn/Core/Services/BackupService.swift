import Foundation
import SwiftData

/// JSON-based backup & restore. Exports the entire model graph to a single
/// `.cairn` document and rebuilds it on import. This is Cairn's manual
/// sync / transfer mechanism (drop the file in iCloud Drive, Dropbox,
/// email, etc.) — the open-source build does not use CloudKit.
@MainActor
public enum BackupService {
    /// Backup format version. Bump when the on-disk schema changes in a
    /// way older builds cannot safely round-trip. Newer files are rejected
    /// by `parse` with `DomainError.backupTooNew` so the user is asked to
    /// upgrade rather than silently losing fields.
    ///
    /// History:
    /// - 1: initial release (members, accounts, holdings, snapshots, FX).
    /// - 2: added `portfolioSnapshots` and `assets` (decoded as nil on
    ///   older clients via optionals).
    /// - 3: added `Member.avatarData`.
    public static let currentVersion: Int = 3
    public static let fileExtension: String = "cairn"
    public static let csvFileExtension: String = "csv"

    // MARK: - Export

    /// Serializes everything currently in `context` to a JSON backup payload.
    public static func makeBackup(in context: ModelContext) throws -> Data {
        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        let snapshots = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []
        let rates = (try? context.fetch(FetchDescriptor<FXRate>())) ?? []
        let portfolioSnapshots = (try? context.fetch(FetchDescriptor<PortfolioSnapshot>())) ?? []
        let assets = (try? context.fetch(FetchDescriptor<Asset>())) ?? []

        let payload = BackupPayload(
            version: currentVersion,
            exportedAt: .now,
            members: members.map(MemberDTO.init),
            accounts: accounts.map(AccountDTO.init),
            holdings: holdings.map(HoldingDTO.init),
            snapshots: snapshots.map(SnapshotDTO.init),
            fxRates: rates.map(FXRateDTO.init),
            portfolioSnapshots: portfolioSnapshots.map(PortfolioSnapshotDTO.init),
            assets: assets.map(AssetDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Exports captured batch snapshots as a wide CSV table. Each row is one
    /// `PortfolioSnapshot`; holding columns are ordered by member, account,
    /// label, then currency, and values remain in each holding's native
    /// currency instead of using `convertedAmount`.
    public static func makeSnapshotCSV(in context: ModelContext) throws -> Data {
        let snapshots = ((try? context.fetch(FetchDescriptor<PortfolioSnapshot>())) ?? [])
            .sorted { lhs, rhs in
                if lhs.periodMonth == rhs.periodMonth {
                    return lhs.recordedAt < rhs.recordedAt
                }
                return lhs.periodMonth < rhs.periodMonth
            }
        let holdingSnapshots = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []

        var columnsByKey: [CSVColumn.Key: CSVColumn] = [:]
        var rateColumnsByKey: [CSVRateColumn.Key: CSVRateColumn] = [:]
        for snapshot in snapshots {
            for entry in snapshot.entries {
                let key = CSVColumn.Key(entry: entry)
                columnsByKey[key] = columnsByKey[key]?.merged(with: entry) ?? CSVColumn(key: key, entry: entry)
            }
            for rate in snapshot.rates {
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

        for snapshot in snapshots {
            let date = batchDate(for: snapshot, holdingSnapshots: holdingSnapshots)
            let rateByKey = Dictionary(
                snapshot.rates.compactMap { rate -> (CSVRateColumn.Key, String)? in
                    guard let key = CSVRateColumn.Key(rate: rate, homeCurrency: snapshot.homeCurrency),
                          let exportRate = foreignToHomeRate(rate, homeCurrency: snapshot.homeCurrency)
                    else { return nil }
                    return (key, rateDecimalString(exportRate))
                },
                uniquingKeysWith: { first, _ in first }
            )
            let amountByKey = Dictionary(
                snapshot.entries.map { (CSVColumn.Key(entry: $0), decimalString($0.amount)) },
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

    // MARK: - Import

    /// Parses a previously exported payload. Does *not* write to the store —
    /// callers decide how to merge (see `restoreReplacing(from:context:)`).
    ///
    /// Throws `DomainError.backupUnreadable` when the bytes are not valid
    /// Cairn backup JSON, and `DomainError.backupTooNew` when the file was
    /// produced by a newer build than this one supports.
    public static func parse(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw DomainError.backupUnreadable
        }
        guard payload.version <= currentVersion else {
            throw DomainError.backupTooNew(
                fileVersion: payload.version,
                supportedVersion: currentVersion
            )
        }
        return payload
    }

    /// Replaces the entire store with the contents of `data`. All existing
    /// members, accounts, holdings, snapshots, and FX rates are deleted
    /// before the backup is inserted. Returns the parsed payload.
    ///
    /// The wipe + insert + save runs inside a single `ModelContext`
    /// transaction so a failure mid-import rolls back to the prior state
    /// instead of leaving the user with an empty store.
    @discardableResult
    public static func restoreReplacing(from data: Data, context: ModelContext) throws -> BackupPayload {
        let payload = try parse(data)
        do {
            try context.transaction {
                wipe(context: context)
                let memberById = insertMembers(payload.members, context: context)
                let accountById = insertAccounts(payload.accounts, memberById: memberById, context: context)
                let holdingById = insertHoldings(payload.holdings, accountById: accountById, context: context)
                insertSnapshots(payload.snapshots, holdingById: holdingById, context: context)
                insertFXRates(payload.fxRates, context: context)
                let portfolioSnapshots = normalizedPortfolioSnapshots(
                    payload.portfolioSnapshots ?? [],
                    members: payload.members,
                    accounts: payload.accounts,
                    holdings: payload.holdings
                )
                insertPortfolioSnapshots(portfolioSnapshots, context: context)
                insertAssets(payload.assets ?? [], memberById: memberById, context: context)
            }
        } catch {
            throw DomainError.backupWriteFailed
        }
        return payload
    }

    // Bottom-up delete to avoid dangling references. Iterates fetched
    // objects so the deletes participate in the surrounding transaction
    // (the `delete(model:)` batch variant bypasses the context cache and
    // is committed eagerly, defeating rollback).
    private static func wipe(context: ModelContext) {
        let portfolio = (try? context.fetch(FetchDescriptor<PortfolioSnapshot>())) ?? []
        portfolio.forEach(context.delete)
        let snapshots = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []
        snapshots.forEach(context.delete)
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        holdings.forEach(context.delete)
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        accounts.forEach(context.delete)
        let assets = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        assets.forEach(context.delete)
        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        members.forEach(context.delete)
        let rates = (try? context.fetch(FetchDescriptor<FXRate>())) ?? []
        rates.forEach(context.delete)
    }

    private static func insertMembers(_ dtos: [MemberDTO], context: ModelContext) -> [UUID: Member] {
        var map: [UUID: Member] = [:]
        for dto in dtos {
            let member = Member(name: dto.name, avatarData: dto.avatarData, createdAt: dto.createdAt)
            member.id = dto.id
            context.insert(member)
            map[dto.id] = member
        }
        return map
    }

    private static func insertAccounts(
        _ dtos: [AccountDTO],
        memberById: [UUID: Member],
        context: ModelContext
    ) -> [UUID: Account] {
        var map: [UUID: Account] = [:]
        for dto in dtos {
            let kind = AccountKind(rawValue: dto.kindRawValue) ?? .cash
            let account = Account(
                name: dto.name,
                kind: kind,
                member: dto.memberId.flatMap { memberById[$0] },
                note: dto.note,
                isArchived: dto.isArchived,
                createdAt: dto.createdAt
            )
            account.id = dto.id
            context.insert(account)
            map[dto.id] = account
        }
        return map
    }

    private static func insertHoldings(
        _ dtos: [HoldingDTO],
        accountById: [UUID: Account],
        context: ModelContext
    ) -> [UUID: Holding] {
        var map: [UUID: Holding] = [:]
        for dto in dtos {
            let holding = Holding(
                currency: dto.currency,
                label: dto.label,
                account: dto.accountId.flatMap { accountById[$0] },
                isArchived: dto.isArchived,
                createdAt: dto.createdAt
            )
            holding.id = dto.id
            context.insert(holding)
            map[dto.id] = holding
        }
        return map
    }

    private static func insertSnapshots(
        _ dtos: [SnapshotDTO],
        holdingById: [UUID: Holding],
        context: ModelContext
    ) {
        for dto in dtos {
            guard let holding = dto.holdingId.flatMap({ holdingById[$0] }) else { continue }
            let snapshot = Snapshot(
                periodMonth: dto.periodMonth,
                amount: dto.amount,
                holding: holding,
                recordedAt: dto.recordedAt
            )
            snapshot.id = dto.id
            context.insert(snapshot)
        }
    }

    private static func insertFXRates(_ dtos: [FXRateDTO], context: ModelContext) {
        for dto in dtos {
            let rate = FXRate(
                base: dto.base,
                quote: dto.quote,
                rate: dto.rate,
                date: dto.date
            )
            rate.id = dto.id
            context.insert(rate)
        }
    }

    private static func insertPortfolioSnapshots(
        _ dtos: [PortfolioSnapshotDTO],
        context: ModelContext
    ) {
        for dto in dtos {
            let snapshot = PortfolioSnapshot(
                periodMonth: dto.periodMonth,
                homeCurrency: dto.homeCurrency,
                totalAmount: dto.totalAmount,
                entries: dto.entries,
                rates: dto.rates,
                note: dto.note,
                recordedAt: dto.recordedAt
            )
            snapshot.id = dto.id
            context.insert(snapshot)
        }
    }

    private static func insertAssets(
        _ dtos: [AssetDTO],
        memberById: [UUID: Member],
        context: ModelContext
    ) {
        for dto in dtos {
            let category = AssetCategory(rawValue: dto.categoryRawValue) ?? .other
            let asset = Asset(
                name: dto.name,
                category: category,
                purchasePrice: dto.purchasePrice,
                purchaseCurrency: dto.purchaseCurrency,
                purchaseDate: dto.purchaseDate,
                currentValue: dto.currentValue,
                currentValueUpdatedAt: dto.currentValueUpdatedAt,
                saleDate: dto.saleDate,
                salePrice: dto.salePrice,
                iconName: dto.iconName,
                note: dto.note,
                member: dto.memberId.flatMap { memberById[$0] },
                createdAt: dto.createdAt
            )
            asset.id = dto.id
            context.insert(asset)
        }
    }

    private struct HoldingIdentityKey: Hashable {
        let memberName: String
        let accountName: String
        let holdingLabel: String
        let currency: String
    }

    private static func normalizedPortfolioSnapshots(
        _ dtos: [PortfolioSnapshotDTO],
        members: [MemberDTO],
        accounts: [AccountDTO],
        holdings: [HoldingDTO]
    ) -> [PortfolioSnapshotDTO] {
        guard !dtos.isEmpty else { return [] }

        let validHoldingIds = Set(holdings.map(\.id))
        let memberById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let accountById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let holdingIdsByIdentity = holdingIdentityIndex(
            holdings: holdings,
            accountById: accountById,
            memberById: memberById
        )

        return dtos.map { dto in
            let entries = dto.entries.map { entry in
                normalizedEntry(
                    entry,
                    validHoldingIds: validHoldingIds,
                    holdingIdsByIdentity: holdingIdsByIdentity
                )
            }
            return PortfolioSnapshotDTO(
                id: dto.id,
                periodMonth: dto.periodMonth,
                homeCurrency: dto.homeCurrency,
                totalAmount: dto.totalAmount,
                note: dto.note,
                recordedAt: dto.recordedAt,
                entries: entries,
                rates: dto.rates
            )
        }
    }

    private static func holdingIdentityIndex(
        holdings: [HoldingDTO],
        accountById: [UUID: AccountDTO],
        memberById: [UUID: MemberDTO]
    ) -> [HoldingIdentityKey: [UUID]] {
        var idsByKey: [HoldingIdentityKey: [UUID]] = [:]
        for holding in holdings {
            let account = holding.accountId.flatMap { accountById[$0] }
            let member = account?.memberId.flatMap { memberById[$0] }
            let key = HoldingIdentityKey(
                memberName: normalizedText(member?.name ?? ""),
                accountName: normalizedText(account?.name ?? ""),
                holdingLabel: normalizedText(holding.label ?? ""),
                currency: holding.currency
            )
            idsByKey[key, default: []].append(holding.id)
        }
        return idsByKey
    }

    private static func normalizedEntry(
        _ entry: PortfolioSnapshot.Entry,
        validHoldingIds: Set<UUID>,
        holdingIdsByIdentity: [HoldingIdentityKey: [UUID]]
    ) -> PortfolioSnapshot.Entry {
        let holdingId = canonicalHoldingId(
            for: entry,
            validHoldingIds: validHoldingIds,
            holdingIdsByIdentity: holdingIdsByIdentity
        )
        return PortfolioSnapshot.Entry(
            id: entry.id,
            holdingId: holdingId,
            memberName: entry.memberName,
            accountName: entry.accountName,
            accountKindRawValue: entry.accountKindRawValue,
            holdingLabel: entry.holdingLabel,
            currency: entry.currency,
            amount: entry.amount,
            convertedAmount: entry.convertedAmount
        )
    }

    private static func canonicalHoldingId(
        for entry: PortfolioSnapshot.Entry,
        validHoldingIds: Set<UUID>,
        holdingIdsByIdentity: [HoldingIdentityKey: [UUID]]
    ) -> UUID? {
        if let holdingId = entry.holdingId, validHoldingIds.contains(holdingId) {
            return holdingId
        }

        let key = HoldingIdentityKey(
            memberName: normalizedText(entry.memberName),
            accountName: normalizedText(entry.accountName),
            holdingLabel: normalizedText(entry.holdingLabel ?? ""),
            currency: entry.currency
        )
        guard let matches = holdingIdsByIdentity[key], matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    private static func batchDate(for snapshot: PortfolioSnapshot, holdingSnapshots: [Snapshot]) -> Date {
        let holdingIds = Set(snapshot.entries.compactMap(\.holdingId))
        guard !holdingIds.isEmpty else { return snapshot.periodMonth }

        let monthStart = snapshot.periodMonth
        let monthEnd = nextMonthStart(after: monthStart)
        let expectedAmountByHoldingId = Dictionary(
            snapshot.entries.compactMap { entry -> (UUID, Decimal)? in
                guard let holdingId = entry.holdingId else { return nil }
                return (holdingId, entry.amount)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var matchesByDate: [Date: Int] = [:]
        for row in holdingSnapshots {
            guard let holdingId = row.holding?.id, holdingIds.contains(holdingId) else { continue }
            guard row.periodMonth >= monthStart && row.periodMonth < monthEnd else { continue }
            guard expectedAmountByHoldingId[holdingId] == row.amount else { continue }
            matchesByDate[row.periodMonth, default: 0] += 1
        }

        return matchesByDate
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .first?.key ?? snapshot.periodMonth
    }

    private static var csvDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static var csvDateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func rateDecimalString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? decimalString(value)
    }

    private static func escapeCSVField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func nextMonthStart(after monthStart: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }
}

// MARK: - Payload

public struct BackupPayload: Codable, Sendable {
    public let version: Int
    public let exportedAt: Date
    public let members: [MemberDTO]
    public let accounts: [AccountDTO]
    public let holdings: [HoldingDTO]
    public let snapshots: [SnapshotDTO]
    public let fxRates: [FXRateDTO]
    /// Added in version 1.1; older backups omit this field entirely, so it
    /// is decoded as `nil` and treated as an empty collection.
    public let portfolioSnapshots: [PortfolioSnapshotDTO]?
    /// Added in version 1.1 with physical-asset support. Older backups omit
    /// this field and decode as `nil`.
    public let assets: [AssetDTO]?

    public init(
        version: Int,
        exportedAt: Date,
        members: [MemberDTO],
        accounts: [AccountDTO],
        holdings: [HoldingDTO],
        snapshots: [SnapshotDTO],
        fxRates: [FXRateDTO],
        portfolioSnapshots: [PortfolioSnapshotDTO]? = nil,
        assets: [AssetDTO]? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.members = members
        self.accounts = accounts
        self.holdings = holdings
        self.snapshots = snapshots
        self.fxRates = fxRates
        self.portfolioSnapshots = portfolioSnapshots
        self.assets = assets
    }
}

public struct MemberDTO: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    /// Added in version 1.2; older backups omit this field entirely and
    /// are decoded with `nil`.
    public let avatarData: Data?

    init(_ member: Member) {
        self.id = member.id
        self.name = member.name
        self.createdAt = member.createdAt
        self.avatarData = member.avatarData
    }
}

public struct AccountDTO: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let kindRawValue: String
    public let note: String?
    public let isArchived: Bool
    public let createdAt: Date
    public let memberId: UUID?

    init(_ account: Account) {
        self.id = account.id
        self.name = account.name
        self.kindRawValue = account.kindRawValue
        self.note = account.note
        self.isArchived = account.isArchived
        self.createdAt = account.createdAt
        self.memberId = account.member?.id
    }
}

public struct HoldingDTO: Codable, Sendable {
    public let id: UUID
    public let currency: String
    public let label: String?
    public let isArchived: Bool
    public let createdAt: Date
    public let accountId: UUID?

    init(_ holding: Holding) {
        self.id = holding.id
        self.currency = holding.currency
        self.label = holding.label
        self.isArchived = holding.isArchived
        self.createdAt = holding.createdAt
        self.accountId = holding.account?.id
    }
}

public struct SnapshotDTO: Codable, Sendable {
    public let id: UUID
    public let amount: Decimal
    public let periodMonth: Date
    public let recordedAt: Date
    public let holdingId: UUID?

    init(_ snapshot: Snapshot) {
        self.id = snapshot.id
        self.amount = snapshot.amount
        self.periodMonth = snapshot.periodMonth
        self.recordedAt = snapshot.recordedAt
        self.holdingId = snapshot.holding?.id
    }
}

public struct FXRateDTO: Codable, Sendable {
    public let id: UUID
    public let base: String
    public let quote: String
    public let rate: Decimal
    public let date: Date

    init(_ rate: FXRate) {
        self.id = rate.id
        self.base = rate.base
        self.quote = rate.quote
        self.rate = rate.rate
        self.date = rate.date
    }
}

public struct PortfolioSnapshotDTO: Codable, Sendable {
    public let id: UUID
    public let periodMonth: Date
    public let homeCurrency: String
    public let totalAmount: Decimal
    public let note: String?
    public let recordedAt: Date
    public let entries: [PortfolioSnapshot.Entry]
    public let rates: [PortfolioSnapshot.Rate]

    public init(
        id: UUID,
        periodMonth: Date,
        homeCurrency: String,
        totalAmount: Decimal,
        note: String?,
        recordedAt: Date,
        entries: [PortfolioSnapshot.Entry],
        rates: [PortfolioSnapshot.Rate]
    ) {
        self.id = id
        self.periodMonth = periodMonth
        self.homeCurrency = homeCurrency
        self.totalAmount = totalAmount
        self.note = note
        self.recordedAt = recordedAt
        self.entries = entries
        self.rates = rates
    }

    init(_ snapshot: PortfolioSnapshot) {
        self.id = snapshot.id
        self.periodMonth = snapshot.periodMonth
        self.homeCurrency = snapshot.homeCurrency
        self.totalAmount = snapshot.totalAmount
        self.note = snapshot.note
        self.recordedAt = snapshot.recordedAt
        self.entries = snapshot.entries
        self.rates = snapshot.rates
    }
}

public struct AssetDTO: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let categoryRawValue: String
    public let purchasePrice: Decimal
    public let purchaseCurrency: String
    public let purchaseDate: Date
    public let currentValue: Decimal?
    public let currentValueUpdatedAt: Date?
    public let saleDate: Date?
    public let salePrice: Decimal?
    public let iconName: String?
    public let note: String?
    public let createdAt: Date
    public let memberId: UUID?

    init(_ asset: Asset) {
        self.id = asset.id
        self.name = asset.name
        self.categoryRawValue = asset.categoryRawValue
        self.purchasePrice = asset.purchasePrice
        self.purchaseCurrency = asset.purchaseCurrency
        self.purchaseDate = asset.purchaseDate
        self.currentValue = asset.currentValue
        self.currentValueUpdatedAt = asset.currentValueUpdatedAt
        self.saleDate = asset.saleDate
        self.salePrice = asset.salePrice
        self.iconName = asset.iconName
        self.note = asset.note
        self.createdAt = asset.createdAt
        self.memberId = asset.member?.id
    }
}

import Foundation
import SwiftData

/// JSON-based backup & restore. Exports the entire model graph to a single
/// `.cairn` document and rebuilds it on import. This is Cairn's manual
/// sync / transfer mechanism (drop the file in iCloud Drive, Dropbox,
/// email, etc.) — the open-source build does not use CloudKit.
@MainActor
public enum BackupService {
    public static let currentVersion: Int = 1
    public static let fileExtension: String = "cairn"

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

    // MARK: - Import

    /// Parses a previously exported payload. Does *not* write to the store —
    /// callers decide how to merge (see `restoreReplacing(from:context:)`).
    public static func parse(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupPayload.self, from: data)
    }

    /// Replaces the entire store with the contents of `data`. All existing
    /// members, accounts, holdings, snapshots, and FX rates are deleted
    /// before the backup is inserted. Returns the parsed payload.
    @discardableResult
    public static func restoreReplacing(from data: Data, context: ModelContext) throws -> BackupPayload {
        let payload = try parse(data)
        try wipe(context: context)
        let memberById = insertMembers(payload.members, context: context)
        let accountById = insertAccounts(payload.accounts, memberById: memberById, context: context)
        let holdingById = insertHoldings(payload.holdings, accountById: accountById, context: context)
        insertSnapshots(payload.snapshots, holdingById: holdingById, context: context)
        insertFXRates(payload.fxRates, context: context)
        insertPortfolioSnapshots(payload.portfolioSnapshots ?? [], context: context)
        insertAssets(payload.assets ?? [], memberById: memberById, context: context)
        try context.save()
        return payload
    }

    // Bottom-up delete to avoid dangling references.
    private static func wipe(context: ModelContext) throws {
        try context.delete(model: PortfolioSnapshot.self)
        try context.delete(model: Snapshot.self)
        try context.delete(model: Holding.self)
        try context.delete(model: Account.self)
        try context.delete(model: Asset.self)
        try context.delete(model: Member.self)
        try context.delete(model: FXRate.self)
    }

    private static func insertMembers(_ dtos: [MemberDTO], context: ModelContext) -> [UUID: Member] {
        var map: [UUID: Member] = [:]
        for dto in dtos {
            let member = Member(name: dto.name, createdAt: dto.createdAt)
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
            context.insert(asset)
        }
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

    init(_ member: Member) {
        self.id = member.id
        self.name = member.name
        self.createdAt = member.createdAt
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

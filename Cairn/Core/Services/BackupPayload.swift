import Foundation

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
    /// Added in version 1.1 with physical-possession support. Older backups omit
    /// this field and decode as `nil`.
    public let possessions: [PossessionDTO]?
    /// Added in version 4. Older backups are replayed from explicit monthly
    /// portfolio snapshots after restore.
    public let achievements: [AchievementEventDTO]?
    /// The exporting device's home currency (ISO 4217). Optional and
    /// additive: older backups omit it, and older builds ignore it, so the
    /// format version is unchanged. Restore applies it only when valid.
    public let homeCurrency: String?

    public init(
        version: Int,
        exportedAt: Date,
        members: [MemberDTO],
        accounts: [AccountDTO],
        holdings: [HoldingDTO],
        snapshots: [SnapshotDTO],
        fxRates: [FXRateDTO],
        portfolioSnapshots: [PortfolioSnapshotDTO]? = nil,
        possessions: [PossessionDTO]? = nil,
        achievements: [AchievementEventDTO]? = nil,
        homeCurrency: String? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.members = members
        self.accounts = accounts
        self.holdings = holdings
        self.snapshots = snapshots
        self.fxRates = fxRates
        self.portfolioSnapshots = portfolioSnapshots
        self.possessions = possessions
        self.achievements = achievements
        self.homeCurrency = homeCurrency
    }
}

public struct AchievementEventDTO: Codable, Sendable {
    public let id: UUID
    public let eventKey: String
    public let familyRawValue: String
    public let stageKey: String
    public let logicalMonth: Date
    public let unlockedAt: Date
    public let currencyCode: String?
    public let observedAmount: Decimal?
    public let sourceRawValue: String
    public let sourceSnapshotIDs: [UUID]
    public let definitionVersion: Int

    init(_ event: AchievementEvent) {
        self.id = event.id
        self.eventKey = event.eventKey
        self.familyRawValue = event.familyRawValue
        self.stageKey = event.stageKey
        self.logicalMonth = event.logicalMonth
        self.unlockedAt = event.unlockedAt
        self.currencyCode = event.currencyCode
        self.observedAmount = event.observedAmount
        self.sourceRawValue = event.sourceRawValue
        self.sourceSnapshotIDs = event.sourceSnapshotIDs
        self.definitionVersion = event.definitionVersion
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

public struct PossessionDTO: Codable, Sendable {
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

    init(_ possession: Possession) {
        self.id = possession.id
        self.name = possession.name
        self.categoryRawValue = possession.categoryRawValue
        self.purchasePrice = possession.purchasePrice
        self.purchaseCurrency = possession.purchaseCurrency
        self.purchaseDate = possession.purchaseDate
        self.currentValue = possession.currentValue
        self.currentValueUpdatedAt = possession.currentValueUpdatedAt
        self.saleDate = possession.saleDate
        self.salePrice = possession.salePrice
        self.iconName = possession.iconName
        self.note = possession.note
        self.createdAt = possession.createdAt
        self.memberId = possession.member?.id
    }
}

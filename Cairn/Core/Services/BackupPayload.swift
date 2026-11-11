import Foundation

struct BackupPayload: Codable, Sendable {
    let version: Int
    let exportedAt: Date
    let members: [MemberDTO]
    let accounts: [AccountDTO]
    let holdings: [HoldingDTO]
    let snapshots: [SnapshotDTO]
    let fxRates: [FXRateDTO]
    /// Added in version 1.1; older backups omit this field entirely, so it
    /// is decoded as `nil` and treated as an empty collection.
    let portfolioSnapshots: [PortfolioSnapshotDTO]?
    /// Added in version 1.1 with physical-possession support. Older backups omit
    /// this field and decode as `nil`.
    let possessions: [PossessionDTO]?
    /// Added in version 4. Older backups are replayed from explicit monthly
    /// portfolio snapshots after restore.
    let achievements: [AchievementEventDTO]?
    /// The exporting device's home currency (ISO 4217). Optional and
    /// additive: older backups omit it, and older builds ignore it, so the
    /// format version is unchanged. Restore applies it only when valid.
    let homeCurrency: String?

    init(
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

struct AchievementEventDTO: Codable, Sendable {
    let id: UUID
    let eventKey: String
    let familyRawValue: String
    let stageKey: String
    let logicalMonth: Date
    let unlockedAt: Date
    let currencyCode: String?
    let observedAmount: Decimal?
    let sourceRawValue: String
    let sourceSnapshotIDs: [UUID]
    let definitionVersion: Int

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

struct MemberDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    /// Added in version 1.2; older backups omit this field entirely and
    /// are decoded with `nil`.
    let avatarData: Data?

    init(_ member: Member) {
        self.id = member.id
        self.name = member.name
        self.createdAt = member.createdAt
        self.avatarData = member.avatarData
    }
}

struct AccountDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let kindRawValue: String
    let note: String?
    let isArchived: Bool
    let createdAt: Date
    let memberId: UUID?

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

struct HoldingDTO: Codable, Sendable {
    let id: UUID
    let currency: String
    let label: String?
    let isArchived: Bool
    let createdAt: Date
    let accountId: UUID?

    init(_ holding: Holding) {
        self.id = holding.id
        self.currency = holding.currency
        self.label = holding.label
        self.isArchived = holding.isArchived
        self.createdAt = holding.createdAt
        self.accountId = holding.account?.id
    }
}

struct SnapshotDTO: Codable, Sendable {
    let id: UUID
    let amount: Decimal
    let periodMonth: Date
    let recordedAt: Date
    let holdingId: UUID?

    init(_ snapshot: Snapshot) {
        self.id = snapshot.id
        self.amount = snapshot.amount
        self.periodMonth = snapshot.periodMonth
        self.recordedAt = snapshot.recordedAt
        self.holdingId = snapshot.holding?.id
    }
}

struct FXRateDTO: Codable, Sendable {
    let id: UUID
    let base: String
    let quote: String
    let rate: Decimal
    let date: Date

    init(_ rate: FXRate) {
        self.id = rate.id
        self.base = rate.base
        self.quote = rate.quote
        self.rate = rate.rate
        self.date = rate.date
    }
}

struct PortfolioSnapshotDTO: Codable, Sendable {
    let id: UUID
    let periodMonth: Date
    let homeCurrency: String
    let totalAmount: Decimal
    let note: String?
    let recordedAt: Date
    let entries: [PortfolioSnapshot.Entry]
    let rates: [PortfolioSnapshot.Rate]

    init(
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

struct PossessionDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let categoryRawValue: String
    let purchasePrice: Decimal
    let purchaseCurrency: String
    let purchaseDate: Date
    let currentValue: Decimal?
    let currentValueUpdatedAt: Date?
    let saleDate: Date?
    let salePrice: Decimal?
    let iconName: String?
    /// Added in version 5; older backups omit this field and decode as `nil`.
    let photoData: Data?
    let note: String?
    let createdAt: Date
    let memberId: UUID?

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
        self.photoData = possession.photoData
        self.note = possession.note
        self.createdAt = possession.createdAt
        self.memberId = possession.member?.id
    }
}

import Foundation
import SwiftData

/// JSON-based backup & restore. Exports the entire model graph to a single
/// `.cairn` document and rebuilds it on import. This is Cairn's manual
/// sync / transfer mechanism (drop the file in iCloud Drive, Dropbox,
/// email, etc.) — the open-source build does not use CloudKit.
@MainActor
enum BackupService {
    /// Backup format version. Bump when the on-disk schema changes in a
    /// way older builds cannot safely round-trip. Newer files are rejected
    /// by `parse` with `DomainError.backupTooNew` so the user is asked to
    /// upgrade rather than silently losing fields.
    ///
    /// History:
    /// - 1: initial release (members, accounts, holdings, snapshots, FX).
    /// - 2: added `portfolioSnapshots` and `possessions` (decoded as nil on
    ///   older clients via optionals).
    /// - 3: added `Member.avatarData`.
    /// - 4: added auditable achievement events. Later gained the optional
    ///   `homeCurrency` setting, which older v4 readers ignore.
    /// - 5: added `Possession.photoData`.
    static let currentVersion: Int = 5
    static let fileExtension: String = "cairn"

    // MARK: - Export

    /// Serializes everything currently in `context`, plus the user's home
    /// currency setting, to a JSON backup payload.
    static func makeBackup(in context: ModelContext, homeCurrency: String) throws -> Data {
        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        let snapshots = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []
        let rates = (try? context.fetch(FetchDescriptor<FXRate>())) ?? []
        let portfolioSnapshots = (try? context.fetch(FetchDescriptor<PortfolioSnapshot>())) ?? []
        let possessions = (try? context.fetch(FetchDescriptor<Possession>())) ?? []
        let achievements = (try? context.fetch(FetchDescriptor<AchievementEvent>())) ?? []

        let payload = BackupPayload(
            version: currentVersion,
            exportedAt: .now,
            members: members.map(MemberDTO.init),
            accounts: accounts.map(AccountDTO.init),
            holdings: holdings.map(HoldingDTO.init),
            snapshots: snapshots.map(SnapshotDTO.init),
            fxRates: rates.map(FXRateDTO.init),
            portfolioSnapshots: portfolioSnapshots.map(PortfolioSnapshotDTO.init),
            possessions: possessions.map(PossessionDTO.init),
            achievements: achievements.map(AchievementEventDTO.init),
            homeCurrency: homeCurrency
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    // MARK: - Import

    /// Parses a previously exported payload. Does *not* write to the store —
    /// callers decide how to merge (see `restoreReplacing(from:context:)`).
    ///
    /// Throws `DomainError.backupUnreadable` when the bytes are not valid
    /// Cairn backup JSON, and `DomainError.backupTooNew` when the file was
    /// produced by a newer build than this one supports.
    static func parse(_ data: Data) throws -> BackupPayload {
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
    static func restoreReplacing(from data: Data, context: ModelContext) throws -> BackupPayload {
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
                insertPossessions(payload.possessions ?? [], memberById: memberById, context: context)
                insertAchievements(payload.achievements ?? [], context: context)
            }
        } catch {
            throw DomainError.backupWriteFailed
        }
        return payload
    }

    /// The backup's home currency when it is a known ISO 4217 code, or
    /// `nil` for older backups and unrecognized values so restore keeps
    /// the current setting.
    static func restorableHomeCurrency(in payload: BackupPayload) -> String? {
        guard let code = payload.homeCurrency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              CurrencyCatalog.all.contains(code) else { return nil }
        return code
    }

    // Bottom-up delete to avoid dangling references. Iterates fetched
    // objects so the deletes participate in the surrounding transaction
    // (the `delete(model:)` batch variant bypasses the context cache and
    // is committed eagerly, defeating rollback).
    private static func wipe(context: ModelContext) {
        let achievements = (try? context.fetch(FetchDescriptor<AchievementEvent>())) ?? []
        achievements.forEach(context.delete)
        let portfolio = (try? context.fetch(FetchDescriptor<PortfolioSnapshot>())) ?? []
        portfolio.forEach(context.delete)
        let snapshots = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []
        snapshots.forEach(context.delete)
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        holdings.forEach(context.delete)
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        accounts.forEach(context.delete)
        let possessions = (try? context.fetch(FetchDescriptor<Possession>())) ?? []
        possessions.forEach(context.delete)
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

    private static func insertPossessions(
        _ dtos: [PossessionDTO],
        memberById: [UUID: Member],
        context: ModelContext
    ) {
        for dto in dtos {
            let category = PossessionCategory(rawValue: dto.categoryRawValue) ?? .other
            let possession = Possession(
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
                photoData: dto.photoData,
                note: dto.note,
                member: dto.memberId.flatMap { memberById[$0] },
                createdAt: dto.createdAt
            )
            possession.id = dto.id
            context.insert(possession)
        }
    }

    private static func insertAchievements(
        _ dtos: [AchievementEventDTO],
        context: ModelContext
    ) {
        for dto in dtos {
            let event = AchievementEvent(
                eventKey: dto.eventKey,
                family: AchievementFamily(rawValue: dto.familyRawValue) ?? .prologue,
                stageKey: dto.stageKey,
                logicalMonth: dto.logicalMonth,
                unlockedAt: dto.unlockedAt,
                currencyCode: dto.currencyCode,
                observedAmount: dto.observedAmount,
                source: AchievementSource(rawValue: dto.sourceRawValue) ?? .imported,
                sourceSnapshotIDs: dto.sourceSnapshotIDs,
                definitionVersion: dto.definitionVersion
            )
            event.id = dto.id
            context.insert(event)
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
}

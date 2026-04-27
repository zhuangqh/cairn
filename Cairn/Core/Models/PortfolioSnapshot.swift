import Foundation
import SwiftData

/// A monthly snapshot of the user's net worth.
///
/// Written whenever the user saves a batch of per-holding values via
/// `BatchEntryView`. One record per `(periodMonth, homeCurrency)`. Each
/// snapshot self-contains the entries (one per active holding at that
/// month) and the FX rates in effect at save time, so later edits to
/// holdings / rates do not silently alter historical records.
///
/// `periodMonth` is normalized to the first day of the month at UTC —
/// see `Snapshot.normalize(_:)`.
@Model
public final class PortfolioSnapshot {
    public var id: UUID = UUID()
    /// Normalized month for this snapshot (month-granular key).
    public var periodMonth: Date = Date()
    /// Wall-clock time the snapshot was saved.
    public var recordedAt: Date = Date()
    /// Home currency at capture time (ISO 4217).
    public var homeCurrency: String = "USD"
    /// Net worth total in `homeCurrency`, precomputed at capture time.
    public var totalAmount: Decimal = 0
    public var note: String?

    /// JSON-encoded `[Entry]`; prefer the `entries` computed accessor.
    public var entriesData: Data = Data()
    /// JSON-encoded `[Rate]`; prefer the `rates` computed accessor.
    public var ratesData: Data = Data()

    public init(
        periodMonth: Date,
        homeCurrency: String,
        totalAmount: Decimal,
        entries: [Entry],
        rates: [Rate],
        note: String? = nil,
        recordedAt: Date = .now
    ) {
        self.id = UUID()
        self.periodMonth = Snapshot.normalize(periodMonth)
        self.homeCurrency = homeCurrency
        self.totalAmount = totalAmount
        self.note = note
        self.recordedAt = recordedAt
        self.entriesData = Self.encode(entries)
        self.ratesData = Self.encode(rates)
    }

    // MARK: - Nested value types

    public struct Entry: Codable, Sendable, Identifiable, Hashable {
        public var id: UUID
        /// Original holding id (may no longer resolve if deleted).
        public var holdingId: UUID?
        public var memberName: String
        public var accountName: String
        /// Captured `AccountKind` raw value at the time of snapshot. Optional
        /// so older snapshots written before this field existed still decode.
        /// Read via the `accountKind` accessor which falls back to `.cash`.
        public var accountKindRawValue: String?
        public var holdingLabel: String?
        public var currency: String
        /// Amount in the holding's native currency.
        public var amount: Decimal
        /// Amount converted to the snapshot's home currency. `nil` when
        /// no FX rate was available at capture time.
        public var convertedAmount: Decimal?

        public init(
            id: UUID = UUID(),
            holdingId: UUID?,
            memberName: String,
            accountName: String,
            accountKindRawValue: String? = nil,
            holdingLabel: String?,
            currency: String,
            amount: Decimal,
            convertedAmount: Decimal?
        ) {
            self.id = id
            self.holdingId = holdingId
            self.memberName = memberName
            self.accountName = accountName
            self.accountKindRawValue = accountKindRawValue
            self.holdingLabel = holdingLabel
            self.currency = currency
            self.amount = amount
            self.convertedAmount = convertedAmount
        }

        /// Resolved `AccountKind`. Returns `nil` for snapshots written
        /// before the field was captured, so callers can choose their own
        /// fallback strategy (e.g. live lookup or `.cash`).
        public var accountKind: AccountKind? {
            accountKindRawValue.flatMap(AccountKind.init(rawValue:))
        }
    }

    public struct Rate: Codable, Sendable, Hashable, Identifiable {
        public var base: String
        public var quote: String
        public var rate: Decimal
        public var id: String { "\(base)->\(quote)" }

        public init(base: String, quote: String, rate: Decimal) {
            self.base = base
            self.quote = quote
            self.rate = rate
        }
    }

    // MARK: - Computed accessors

    public var entries: [Entry] {
        get { Self.decode([Entry].self, from: entriesData) ?? [] }
        set { entriesData = Self.encode(newValue) }
    }

    public var rates: [Rate] {
        get { Self.decode([Rate].self, from: ratesData) ?? [] }
        set { ratesData = Self.encode(newValue) }
    }

    // MARK: - Coding helpers

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

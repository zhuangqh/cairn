import Foundation
import SwiftData

/// A single-currency position within an `Account`. Smallest unit of entry and trend.
///
/// Invariants (see PRD §3.3):
/// - `currency` is immutable once created (archive + recreate to change).
/// - Within one `Account`, no two `Holding`s may share the same `currency`.
///   Enforced in UI + validated on save (no CloudKit-compatible unique constraint).
@Model
public final class Holding {
    public var id: UUID = UUID()
    /// ISO 4217 code, e.g. `"CNY"`, `"AUD"`, `"USD"`.
    public var currency: String = "USD"
    public var label: String?
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    @Relationship public var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Snapshot.holding)
    public var snapshots: [Snapshot]? = []

    public init(
        currency: String,
        label: String? = nil,
        account: Account? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.currency = currency
        self.label = label
        self.account = account
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.snapshots = []
    }
}

import Foundation
import SwiftData

/// A single-currency position within an `Account`. Smallest unit of entry and trend.
///
/// Invariants (see PRD §3.3):
/// - `currency` is immutable once created (archive + recreate to change).
/// - Within one `Account`, no two `Holding`s may share the same `currency`.
///   Enforced in UI + validated on save (no CloudKit-compatible unique constraint).
@Model
final class Holding {
    var id: UUID = UUID()
    /// ISO 4217 code, e.g. `"CNY"`, `"AUD"`, `"USD"`.
    var currency: String = "USD"
    var label: String?
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Snapshot.holding)
    var snapshots: [Snapshot]? = []

    init(
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

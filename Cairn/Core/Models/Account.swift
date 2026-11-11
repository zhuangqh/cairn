import Foundation
import SwiftData

/// A container under a `Member` (cash / equity / real estate / device).
///
/// An `Account` is **not** bound to a currency. Multi-currency is modeled via multiple `Holding`s.
/// Persisted as a stable `kindRawValue` token; expose `kind` as the typed accessor.
@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRawValue: String = AccountKind.cash.rawValue
    var note: String?
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship var member: Member?

    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    var holdings: [Holding]? = []

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRawValue) ?? .cash }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        name: String,
        kind: AccountKind,
        member: Member? = nil,
        note: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.kindRawValue = kind.rawValue
        self.member = member
        self.note = note
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.holdings = []
    }
}

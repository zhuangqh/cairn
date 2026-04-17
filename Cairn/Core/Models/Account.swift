import Foundation
import SwiftData

/// A container under a `Member` (cash / equity / real estate / device).
///
/// An `Account` is **not** bound to a currency. Multi-currency is modeled via multiple `Holding`s.
/// Persisted as a stable `kindRawValue` token; expose `kind` as the typed accessor.
@Model
public final class Account {
    public var id: UUID = UUID()
    public var name: String = ""
    public var kindRawValue: String = AccountKind.cash.rawValue
    public var note: String?
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    @Relationship public var member: Member?

    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    public var holdings: [Holding]? = []

    public var kind: AccountKind {
        get { AccountKind(rawValue: kindRawValue) ?? .cash }
        set { kindRawValue = newValue.rawValue }
    }

    public init(
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

import Foundation
import SwiftData

/// Family member — top-level data isolation unit.
///
/// Note: CloudKit-backed SwiftData requires every stored property to have a default value and
/// every to-many relationship to be an optional array. See PRD §3.3 / §9.1 (CloudKit sync).
@Model
public final class Member {
    public var id: UUID = UUID()
    public var name: String = ""
    public var avatarData: Data?
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Account.member)
    public var accounts: [Account]? = []

    @Relationship(deleteRule: .cascade, inverse: \Asset.member)
    public var assets: [Asset]? = []

    public init(name: String, avatarData: Data? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.avatarData = avatarData
        self.createdAt = createdAt
        self.accounts = []
        self.assets = []
    }
}

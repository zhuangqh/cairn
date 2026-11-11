import Foundation
import SwiftData

/// Family member — top-level data isolation unit.
///
/// Note: CloudKit-backed SwiftData requires every stored property to have a default value and
/// every to-many relationship to be an optional array. See PRD §3.3 / §9.1 (CloudKit sync).
@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""
    var avatarData: Data?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Account.member)
    var accounts: [Account]? = []

    @Relationship(deleteRule: .cascade, inverse: \Possession.member)
    var possessions: [Possession]? = []

    init(name: String, avatarData: Data? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.avatarData = avatarData
        self.createdAt = createdAt
        self.accounts = []
        self.possessions = []
    }
}

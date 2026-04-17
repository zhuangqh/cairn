import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// The production configuration syncs with CloudKit through the entitlement
/// `iCloud.com.cairn.app`. Use `.inMemory()` for previews and tests.
public enum PersistenceController {
    /// Ordered schema of models used by the app. Add new models here on every migration.
    public static let schema = Schema([
        Member.self,
        Account.self,
        Holding.self,
        Snapshot.self,
        FXRate.self
    ])

    public enum Mode {
        case cloud
        case localOnly
        case inMemory
    }

    public static func makeContainer(_ mode: Mode = .cloud) throws -> ModelContainer {
        let configuration: ModelConfiguration
        switch mode {
        case .cloud:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        case .localOnly:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        case .inMemory:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// In-memory container with no CloudKit — for SwiftUI previews and unit tests.
    public static func previewContainer() -> ModelContainer {
        do {
            return try makeContainer(.inMemory)
        } catch {
            fatalError("Failed to build preview ModelContainer: \(error)")
        }
    }
}

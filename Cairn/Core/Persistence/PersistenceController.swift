import Foundation
import SwiftData

/// Builds the app's `ModelContainer`. Cairn stores data locally in the
/// user's Application Support directory; cross-device sync is intentionally
/// left to the user via the backup file (see `BackupService`).
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
        case localOnly
        case inMemory
    }

    public static func makeContainer(_ mode: Mode = .localOnly) throws -> ModelContainer {
        let configuration: ModelConfiguration
        switch mode {
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

    /// In-memory container — for SwiftUI previews and unit tests.
    public static func previewContainer() -> ModelContainer {
        do {
            return try makeContainer(.inMemory)
        } catch {
            fatalError("Failed to build preview ModelContainer: \(error)")
        }
    }
}

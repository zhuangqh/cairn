import SwiftUI
import SwiftData

@main
struct CairnApp: App {
    @State private var localization = LocalizationService()

    private let container: ModelContainer = {
        do {
            return try PersistenceController.makeContainer(.cloud)
        } catch {
            // Fall back to local-only storage so the app stays usable if CloudKit init fails
            // (e.g. missing entitlement during early development).
            // TODO: surface a diagnostic to the user in M6.
            do {
                return try PersistenceController.makeContainer(.localOnly)
            } catch {
                fatalError("Failed to initialize persistence: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(localization)
                .environment(\.locale, localization.effectiveLocale ?? Locale.current)
        }
        .modelContainer(container)
    }
}

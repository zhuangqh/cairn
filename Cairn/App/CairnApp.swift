import SwiftUI
import SwiftData

@main
struct CairnApp: App {
    @State private var localization = LocalizationService()

    private let container: ModelContainer = {
        do {
            return try PersistenceController.makeContainer(.localOnly)
        } catch {
            fatalError("Failed to initialize persistence: \(error)")
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

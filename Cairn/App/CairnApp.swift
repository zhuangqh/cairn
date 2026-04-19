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
                // Enforce a sensible minimum size so the responsive layout
                // never gets squeezed below its compact breakpoint.
                .frame(minWidth: 720, minHeight: 520)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}

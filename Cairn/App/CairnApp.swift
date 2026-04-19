import SwiftUI
import SwiftData

@main
struct CairnApp: App {
    @State private var localization = LocalizationService()

    @AppStorage(AppSettingsKeys.appearance)
    private var appearanceRaw: String = AppAppearance.default.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .default
    }

    private let container: ModelContainer = {
        do {
            return try PersistenceController.makeContainer(.localOnly)
        } catch {
            fatalError("Failed to initialize persistence: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            rootScene
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }

    @ViewBuilder
    private var rootScene: some View {
        let root = RootView()
            .environment(localization)
            .environment(\.locale, localization.effectiveLocale ?? Locale.current)
            .preferredColorScheme(appearance.colorScheme)
        #if os(macOS)
        // Enforce a sensible minimum window size on macOS so the responsive
        // layout never gets squeezed below its compact breakpoint. Do NOT
        // apply on iOS — would force the UI wider than the device screen.
        root.frame(minWidth: 720, minHeight: 520)
        #else
        root
        #endif
    }
}

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
        #if DEBUG
        // Visual-review launches (scripts/screenshot-*.sh) use in-memory data
        // so they never open or modify the user's store: the mock backup
        // passed with `-CairnMockData <path>`, or the built-in preview graph.
        if let path = UserDefaults.standard.string(forKey: "CairnMockData") {
            return MainActor.assumeIsolated {
                PreviewSampleData.mockContainer(contentsOf: URL(fileURLWithPath: path))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-CairnSampleData") {
            return MainActor.assumeIsolated { PreviewSampleData.container() }
        }
        #endif
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

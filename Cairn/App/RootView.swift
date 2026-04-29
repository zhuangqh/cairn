import SwiftUI

/// Top-level navigation shell. On macOS it uses a `NavigationSplitView`
/// with a sidebar. On iOS/iPadOS it uses a bottom `TabView`, which is the
/// platform-native pattern and avoids `List(selection:)` being unavailable
/// on iOS outside of a split-view sidebar.
struct RootView: View {
    @AppStorage(AppSettingsKeys.onboardingCompleted)
    private var onboardingCompleted: Bool = false

    @AppStorage(AppSettingsKeys.featureTourSeen)
    private var featureTourSeen: Bool = false

    @State private var selection: SidebarItem = .dashboard

    /// First-run sheet selection. Drives the highlights tour first, then the
    /// setup wizard. Resolves to `nil` once both are complete.
    private enum FirstRunSheet: String, Identifiable {
        case tour, setup
        var id: String { rawValue }
    }

    private var firstRunSheet: FirstRunSheet? {
        if !featureTourSeen { return .tour }
        if !onboardingCompleted { return .setup }
        return nil
    }

    var body: some View {
        shell
            .sheet(item: .init(
                get: { firstRunSheet },
                set: { _ in }
            )) { sheet in
                switch sheet {
                case .tour:
                    FeatureTourView()
                case .setup:
                    OnboardingView()
                }
            }
    }

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        macShell
        #else
        iosShell
        #endif
    }

    #if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @ViewBuilder
    private var macShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail(for: selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    Label {
                        Text(LocalizedStringKey(item.titleKey))
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                    .tag(item)
                }
            } header: {
                Text("app.name")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("app.name")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }
    #endif

    #if !os(macOS)
    @ViewBuilder
    private var iosShell: some View {
        TabView(selection: $selection) {
            ForEach(SidebarItem.allCases, id: \.self) { item in
                detail(for: item)
                    .tabItem {
                        Label {
                            Text(LocalizedStringKey(item.titleKey))
                        } icon: {
                            Image(systemName: item.systemImage)
                        }
                    }
                    .tag(item)
            }
        }
    }
    #endif

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard:
            NavigationStack { DashboardView() }
        case .overview:
            NavigationStack { OverviewView() }
        case .accounts:
            NavigationStack { MembersListView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }
}

enum SidebarItem: CaseIterable, Hashable {
    case dashboard
    case overview
    case accounts
    case settings

    var titleKey: String {
        switch self {
        case .dashboard: return "dashboard.title"
        case .overview: return "overview.title"
        case .accounts: return "accounts.title"
        case .settings: return "settings.title"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .overview: return "chart.line.uptrend.xyaxis"
        case .accounts: return "wallet.pass"
        case .settings: return "gearshape"
        }
    }
}

#if DEBUG
#Preview("RootView · seeded") {
    PreviewDefaults.primeOnboarded()
    return RootView()
        .environment(LocalizationService())
        .modelContainer(PreviewSampleData.container())
}

#Preview("RootView · first run") {
    UserDefaults.standard.set(false, forKey: AppSettingsKeys.onboardingCompleted)
    UserDefaults.standard.set(false, forKey: AppSettingsKeys.featureTourSeen)
    return RootView()
        .environment(LocalizationService())
        .modelContainer(PreviewSampleData.emptyContainer())
}
#endif

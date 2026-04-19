import SwiftUI

/// Top-level navigation shell. Uses a sidebar layout on macOS / iPad that
/// collapses into a stack on compact iPhone widths. The detail column
/// renders the feature selected in the sidebar.
struct RootView: View {
    @AppStorage(AppSettingsKeys.onboardingCompleted)
    private var onboardingCompleted: Bool = false

    @State private var selection: SidebarItem = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: .init(
            get: { !onboardingCompleted },
            set: { _ in }
        )) {
            OnboardingView()
        }
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

    @ViewBuilder
    private var detail: some View {
        switch selection {
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

#Preview {
    RootView()
        .environment(LocalizationService())
        .modelContainer(PersistenceController.previewContainer())
}

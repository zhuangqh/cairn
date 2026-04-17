import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            OverviewView()
                .tabItem {
                    Label("overview.title", systemImage: "chart.line.uptrend.xyaxis")
                }

            AccountsView()
                .tabItem {
                    Label("accounts.title", systemImage: "wallet.pass")
                }

            SettingsView()
                .tabItem {
                    Label("settings.title", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    RootView()
        .environment(LocalizationService())
        .modelContainer(PersistenceController.previewContainer())
}

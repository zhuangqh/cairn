import SwiftUI

struct RootView: View {
    @AppStorage(AppSettingsKeys.onboardingCompleted)
    private var onboardingCompleted: Bool = false

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
        .sheet(isPresented: .init(
            get: { !onboardingCompleted },
            set: { _ in }
        )) {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .environment(LocalizationService())
        .modelContainer(PersistenceController.previewContainer())
}

import SwiftUI

/// Top-level navigation shell. On macOS it uses a `NavigationSplitView`
/// with a sidebar. On iOS/iPadOS it uses a bottom `TabView`, which is the
/// platform-native pattern and avoids `List(selection:)` being unavailable
/// on iOS outside of a split-view sidebar.
struct RootView: View {
    @Environment(LocalizationService.self) private var localization

    @AppStorage(AppSettingsKeys.onboardingCompleted)
    private var onboardingCompleted: Bool = false

    @AppStorage(AppSettingsKeys.featureTourSeen)
    private var featureTourSeen: Bool = false

    @State private var selection: SidebarItem = .dashboard

    /// First-run sheet is the unified `FeatureTourView` running in
    /// `.firstRun` mode, which itself rolls highlights → home currency →
    /// first member into a single carousel. The sheet stays up until both
    /// the tour has been seen and onboarding setup has completed.
    private var showsFirstRun: Bool {
        !featureTourSeen || !onboardingCompleted
    }

    var body: some View {
        shell
            .tint(Color.notionBlue)
            .sheet(isPresented: .init(
                get: { showsFirstRun },
                set: { _ in }
            )) {
                FeatureTourView(mode: .firstRun)
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
    @State private var hoveredSidebarItem: SidebarItem?

    private let primarySidebarItems: [SidebarItem] = [
        .dashboard,
        .assets,
        .accounts
    ]

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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.notionBlue)

                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(y: 1)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("app.name", bundle: localization.bundle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.notionInk)

                    Text("dashboard.totalWealth", bundle: localization.bundle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.notionInkMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 20)

            VStack(spacing: 5) {
                ForEach(primarySidebarItems, id: \.self) { item in
                    sidebarButton(for: item)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 24)

            Divider()
                .overlay(Color.notionBorder)
                .padding(.horizontal, 16)

            sidebarButton(for: .settings)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
        .navigationSplitViewColumnWidth(min: 218, ideal: 236, max: 280)
    }

    private func sidebarButton(for item: SidebarItem) -> some View {
        let isSelected = selection == item
        let isHovered = hoveredSidebarItem == item

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                selection = item
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.notionBlue : Color.notionInkSecondary)
                    .frame(width: 22, height: 22)

                Text(LocalizedStringKey(item.titleKey), bundle: localization.bundle)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.notionInk : Color.notionInkSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background {
                sidebarRowBackground(isSelected: isSelected, isHovered: isHovered)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                hoveredSidebarItem = hovering ? item : nil
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func sidebarRowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        if isSelected {
            shape.fill(Color.notionBlue.opacity(0.11))
        } else if isHovered {
            shape.fill(Color.primary.opacity(0.045))
        } else {
            Color.clear
        }
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
                            Text(LocalizedStringKey(item.titleKey), bundle: localization.bundle)
                        } icon: {
                            Image(systemName: item.systemImage)
                        }
                    }
                    .tag(item)
            }
        }
        .cairnTabBarBehavior()
    }
    #endif

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard:
            NavigationStack { DashboardView() }
        case .assets:
            NavigationStack { AssetsView() }
        case .accounts:
            NavigationStack { MembersListView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }
}

#if os(iOS)
private extension View {
    /// iOS 26's floating Liquid Glass tab bar can collapse while the user is
    /// reading long charts and lists, returning that space to the content.
    @ViewBuilder
    func cairnTabBarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
#endif

enum SidebarItem: CaseIterable, Hashable {
    case dashboard
    case assets
    case accounts
    case settings

    var titleKey: String {
        switch self {
        case .dashboard: return "dashboard.title"
        case .assets: return "assets.title"
        case .accounts: return "accounts.title"
        case .settings: return "settings.title"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .assets: return "chart.line.uptrend.xyaxis"
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

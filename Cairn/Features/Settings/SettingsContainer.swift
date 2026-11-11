import SwiftUI

/// Settings chrome. iOS shows flat rows on the ivory ground — no inset
/// cards — separated by hairlines (§5.11); macOS keeps its grouped form.
struct SettingsContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(iOS)
        List {
            content()
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.line)
                .listSectionSeparator(.hidden)
        }
        .listStyle(.grouped)
        .glassListStyle()
        #else
        Form {
            content()
        }
        .formStyle(.grouped)
        .glassListStyle()
        #endif
    }
}

import SwiftUI

struct SettingsView: View {
    @Environment(LocalizationService.self) private var localization

    var body: some View {
        @Bindable var localization = localization

        NavigationStack {
            Form {
                Section("settings.section.general") {
                    Picker(selection: $localization.override) {
                        ForEach(LocalizationService.LanguageOverride.allCases, id: \.self) { option in
                            Text(LocalizedStringKey(option.localizationKey))
                                .tag(option)
                        }
                    } label: {
                        Text("settings.language.title")
                    }
                }
            }
            .navigationTitle("settings.title")
        }
    }
}

#Preview {
    SettingsView()
        .environment(LocalizationService())
}

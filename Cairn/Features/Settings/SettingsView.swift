import SwiftUI
import SwiftData

/// Pages Settings pushes. Value-based so the macOS sidebar can reset them
/// (see `RootView`).
enum SettingsRoute: Hashable {
    case homeCurrency
}

struct SettingsView: View {
    fileprivate static let repositoryURL = externalURL("https://github.com/zhuangqh/cairn")
    fileprivate static let starURL = externalURL("https://github.com/zhuangqh/cairn/stargazers")
    fileprivate static let bugReportURL = externalURL("https://github.com/zhuangqh/cairn/issues/new")

    private static func externalURL(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    @Environment(LocalizationService.self) private var localization
    @Environment(\.modelContext) var context

    @AppStorage(AppSettingsKeys.homeCurrency)
    var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

    @AppStorage(AppSettingsKeys.appearance)
    private var appearanceRaw: String = AppAppearance.default.rawValue

    @AppStorage(AppSettingsKeys.reminderEnabled)
    private var reminderEnabled: Bool = false

    @AppStorage(AppSettingsKeys.reminderHour)
    private var reminderHour: Int = AppSettingsKeys.defaultReminderHour

    @AppStorage(AppSettingsKeys.reminderMinute)
    private var reminderMinute: Int = AppSettingsKeys.defaultReminderMinute

    @AppStorage(AppSettingsKeys.reminderDay)
    private var reminderDay: Int = AppSettingsKeys.defaultReminderDay

    @State var exportDocument: BackupDocument?
    @State var csvExportDocument: CSVExportDocument?
    @State var isExporting: Bool = false
    @State var isExportingCSV: Bool = false
    @State private var isImporting: Bool = false
    @State var importConfirmation: Data?
    @State var resultMessage: LocalizedStringKey?
    @State private var isShowingFeatureTour: Bool = false
    @State var importedAchievements: [AchievementPresentation] = []
    @State var isShowingImportSummary: Bool = false
    /// Last reminder configuration seen by the reminder task. `nil` until
    /// first appearance, which only records the baseline (matching the
    /// former `onChange` handlers, which never fired initially).
    @State private var appliedReminderConfig: ReminderConfig?

    private struct ReminderConfig: Equatable {
        let enabled: Bool
        let day: Int
        let hour: Int
        let minute: Int
    }

    private var reminderConfig: ReminderConfig {
        ReminderConfig(enabled: reminderEnabled, day: reminderDay, hour: reminderHour, minute: reminderMinute)
    }

    var body: some View {
        @Bindable var localization = localization

        SettingsContainer {
            Section {
                Picker(selection: $localization.override) {
                    ForEach(LocalizationService.LanguageOverride.allCases, id: \.self) { option in
                        Text(LocalizedStringKey(option.localizationKey))
                            .tag(option)
                    }
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.language.title",
                        systemImage: "globe"
                    )
                }

                NavigationLink(value: SettingsRoute.homeCurrency) {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.homeCurrency.title",
                            systemImage: "dollarsign.circle"
                        )
                        Spacer(minLength: 12)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: homeCurrency)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Color.ink)
                            Text(verbatim: CurrencyCatalog.displayName(homeCurrency))
                                .font(.callout)
                                .foregroundStyle(Color.ink2)
                                .lineLimit(1)
                        }
                    }
                }

                Picker(selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        Text(LocalizedStringKey(option.localizationKey))
                            .tag(option)
                    }
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.appearance.title",
                        systemImage: "circle.righthalf.filled"
                    )
                }
            } header: {
                sectionHeader("settings.section.general")
            }

            Section {
                Toggle(isOn: $reminderEnabled) {
                    settingsRowLabel(
                        titleKey: "settings.reminder.toggle",
                        systemImage: "bell"
                    )
                }
                if reminderEnabled {
                    Picker(selection: $reminderDay) {
                        ForEach(1...AppSettingsKeys.reminderDayMax, id: \.self) { day in
                            Text(day, format: .number).tag(day)
                        }
                    } label: {
                        settingsRowLabel(
                            titleKey: "settings.reminder.day",
                            systemImage: "calendar"
                        )
                    }
                    .pickerStyle(.menu)

                    DatePicker(
                        selection: reminderTimeBinding,
                        displayedComponents: [.hourAndMinute]
                    ) {
                        settingsRowLabel(
                            titleKey: "settings.reminder.time",
                            systemImage: "clock"
                        )
                    }
                }
            } header: {
                sectionHeader("settings.section.reminder")
            } footer: {
                sectionFooter("settings.reminder.footer")
            }
            .task(id: reminderConfig) {
                await applyReminderIfChanged(reminderConfig)
            }

            Section {
                Button {
                    beginExport()
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.backup.export",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    beginCSVExport()
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.backup.exportCSV",
                        systemImage: "tablecells"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isImporting = true
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.backup.import",
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(.plain)
            } header: {
                sectionHeader("settings.section.backup")
            } footer: {
                sectionFooter("settings.backup.footer")
            }

            Section {
                Button {
                    isShowingFeatureTour = true
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.featureTour.show",
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(.plain)
            } header: {
                sectionHeader("settings.section.help")
            } footer: {
                sectionFooter("settings.featureTour.footer")
            }

            Section {
                LabeledContent {
                    Text(verbatim: appVersion)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Color.ink2)
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.about.version",
                        systemImage: "info.circle"
                    )
                }

                Link(destination: Self.repositoryURL) {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.about.sourceCode",
                            systemImage: "chevron.left.forwardslash.chevron.right"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ink3)
                    }
                }
                .buttonStyle(.plain)

                Link(destination: Self.starURL) {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.about.star",
                            systemImage: "star"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ink3)
                    }
                }
                .buttonStyle(.plain)

                Link(destination: Self.bugReportURL) {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.about.bugReport",
                            systemImage: "ladybug"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ink3)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                sectionHeader("settings.section.about")
            } footer: {
                sectionFooter("settings.about.footer")
            }
        }
        .navigationTitle(Text("settings.title", bundle: localization.bundle))
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .homeCurrency: CurrencyPickerView(selection: $homeCurrency)
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultExportFilename(stem: "cairn-backup", fileExtension: "cairn")
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                resultMessage = "settings.backup.export.success"
            case .failure:
                resultMessage = "settings.backup.export.failure"
            }
        }
        .fileExporter(
            isPresented: $isExportingCSV,
            document: csvExportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: defaultExportFilename(stem: "cairn-snapshots", fileExtension: "csv")
        ) { result in
            csvExportDocument = nil
            switch result {
            case .success:
                resultMessage = "settings.backup.exportCSV.success"
            case .failure:
                resultMessage = "settings.backup.export.failure"
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadImportCandidate(from: url)
            case .failure:
                resultMessage = "settings.backup.import.failure"
            }
        }
        .alert(
            "settings.backup.import.confirm.title",
            isPresented: Binding(isPresent: $importConfirmation)
        ) {
            Button(role: .destructive) {
                performRestore()
            } label: {
                Text("settings.backup.import.confirm.action")
            }
            Button(role: .cancel) {
                importConfirmation = nil
            } label: {
                Text("common.action.cancel")
            }
        } message: {
            Text("settings.backup.import.confirm.message")
        }
        .alert(
            resultMessage ?? "",
            isPresented: Binding(isPresent: $resultMessage)
        ) {
            Button {
                resultMessage = nil
            } label: {
                Text("common.action.done")
            }
        }
        .sheet(isPresented: $isShowingFeatureTour) {
            FeatureTourView(mode: .replay)
        }
        .sheet(isPresented: $isShowingImportSummary) {
            AchievementImportSummaryView(events: importedAchievements) {
                isShowingImportSummary = false
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Helpers

    /// Row label (§5.11): 22pt monochrome line icon in `ink2`, then the title.
    private func settingsRowLabel(
        titleKey: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.ink2)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.body)
                .foregroundStyle(Color.ink)
        }
    }

    /// 20pt bold section title (§3), sentence case.
    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.title3.bold())
            .tracking(-0.2)
            .foregroundStyle(Color.ink)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .overlay(alignment: .top) { LedgerHairline() }
            .accessibilityAddTraits(.isHeader)
    }

    /// Supplementary note at the end of a section (§5.11).
    private func sectionFooter(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.footnote)
            .foregroundStyle(Color.ink3)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .default },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = reminderHour
                components.minute = reminderMinute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? AppSettingsKeys.defaultReminderHour
                reminderMinute = components.minute ?? AppSettingsKeys.defaultReminderMinute
            }
        )
    }

    private func applyReminderIfChanged(_ config: ReminderConfig) async {
        guard let previous = appliedReminderConfig else {
            appliedReminderConfig = config
            return
        }
        guard previous != config else { return }
        appliedReminderConfig = config
        await applyReminder(enabled: config.enabled)
    }

    private func applyReminder(enabled: Bool) async {
        if enabled {
            let granted = await ReminderService.requestAuthorization()
            // A newer configuration replaced this task; let it apply instead.
            guard !Task.isCancelled else { return }
            if granted {
                await ReminderService.schedule(day: reminderDay, hour: reminderHour, minute: reminderMinute)
            } else {
                reminderEnabled = false
                resultMessage = "settings.reminder.denied"
            }
        } else {
            ReminderService.cancel()
        }
    }
}

#Preview {
    SettingsView()
        .environment(LocalizationService())
        .modelContainer(PreviewSampleData.container())
}

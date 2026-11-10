import SwiftUI
import SwiftData

struct SettingsView: View {
    fileprivate static let repositoryURL = externalURL("https://github.com/zhuangqh/cairn")
    fileprivate static let starURL = externalURL("https://github.com/zhuangqh/cairn/stargazers")
    fileprivate static let bugReportURL = externalURL("https://github.com/zhuangqh/cairn/issues/new")

    private static func externalURL(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    @Environment(LocalizationService.self) private var localization
    @Environment(\.modelContext) private var context

    @AppStorage(AppSettingsKeys.homeCurrency)
    private var homeCurrency: String = AppSettingsKeys.defaultHomeCurrency

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

    @State private var exportDocument: BackupDocument?
    @State private var csvExportDocument: CSVExportDocument?
    @State private var isExporting: Bool = false
    @State private var isExportingCSV: Bool = false
    @State private var isImporting: Bool = false
    @State private var importConfirmation: Data?
    @State private var resultMessage: LocalizedStringKey?
    @State private var isShowingFeatureTour: Bool = false
    @State private var importedAchievements: [AchievementPresentation] = []
    @State private var isShowingImportSummary: Bool = false

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

                NavigationLink {
                    CurrencyPickerView(selection: $homeCurrency)
                } label: {
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
            .onChange(of: reminderEnabled) { _, newValue in
                Task { await applyReminder(enabled: newValue) }
            }
            .onChange(of: reminderHour) { _, _ in
                Task { await applyReminder(enabled: reminderEnabled) }
            }
            .onChange(of: reminderMinute) { _, _ in
                Task { await applyReminder(enabled: reminderEnabled) }
            }
            .onChange(of: reminderDay) { _, _ in
                Task { await applyReminder(enabled: reminderEnabled) }
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
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultExportFilename()
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
            defaultFilename: defaultCSVExportFilename()
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
            isPresented: .init(
                get: { importConfirmation != nil },
                set: { if !$0 { importConfirmation = nil } }
            )
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
            isPresented: .init(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
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

    private var reminderTimeBinding: Binding<Date> {        Binding(
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

    private func applyReminder(enabled: Bool) async {
        if enabled {
            let granted = await ReminderService.requestAuthorization()
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

    // MARK: - Backup

    @MainActor
    private func beginExport() {
        do {
            let data = try BackupService.makeBackup(in: context, homeCurrency: homeCurrency)
            exportDocument = BackupDocument(data: data)
            isExporting = true
        } catch {
            resultMessage = "settings.backup.export.failure"
        }
    }

    @MainActor
    private func beginCSVExport() {
        do {
            let data = try BackupService.makeSnapshotCSV(in: context)
            csvExportDocument = CSVExportDocument(data: data)
            isExportingCSV = true
        } catch {
            resultMessage = "settings.backup.export.failure"
        }
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "cairn-backup-\(formatter.string(from: .now)).cairn"
    }

    private func defaultCSVExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "cairn-snapshots-\(formatter.string(from: .now)).csv"
    }

    private func loadImportCandidate(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            _ = try BackupService.parse(data)
            importConfirmation = data
        } catch let error as DomainError {
            resultMessage = LocalizedStringKey(error.localizationKey)
        } catch {
            resultMessage = "settings.backup.import.failure"
        }
    }

    @MainActor
    private func performRestore() {
        guard let data = importConfirmation else { return }
        importConfirmation = nil
        do {
            let payload = try BackupService.restoreReplacing(from: data, context: context)
            if let restoredCurrency = BackupService.restorableHomeCurrency(in: payload) {
                homeCurrency = restoredCurrency
            }
            _ = try AchievementService.recompute(in: context, source: .imported)
            importedAchievements = AchievementService.allPresentations(in: context)
            isShowingImportSummary = true
        } catch let error as DomainError {
            resultMessage = LocalizedStringKey(error.localizationKey)
        } catch {
            resultMessage = "settings.backup.import.failure"
        }
    }
}

private struct CurrencyPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("currency.picker.pinned") {
                ForEach(CurrencyCatalog.pinned, id: \.self) { code in
                    row(code)
                }
            }
            Section("currency.picker.other") {
                ForEach(CurrencyCatalog.rest, id: \.self) { code in
                    row(code)
                }
            }
        }
        .navigationTitle("currency.picker.title")
    }

    private func row(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: code)
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, alignment: .leading)
                Text(verbatim: CurrencyCatalog.displayName(code))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environment(LocalizationService())
        .modelContainer(PreviewSampleData.container())
}

/// Settings chrome. iOS shows flat rows on the ivory ground — no inset
/// cards — separated by hairlines (§5.11); macOS keeps its grouped form.
private struct SettingsContainer<Content: View>: View {
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

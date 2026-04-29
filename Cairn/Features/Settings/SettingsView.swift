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

    var body: some View {
        @Bindable var localization = localization

        Form {
            Section {
                Picker(selection: $localization.override) {
                    ForEach(LocalizationService.LanguageOverride.allCases, id: \.self) { option in
                        Text(LocalizedStringKey(option.localizationKey))
                            .tag(option)
                    }
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.language.title",
                        systemImage: "globe",
                        tint: .notionBlue
                    )
                }

                NavigationLink {
                    CurrencyPickerView(selection: $homeCurrency)
                } label: {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.homeCurrency.title",
                            systemImage: "dollarsign.circle.fill",
                            tint: .notionGreen
                        )
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: homeCurrency)
                                .font(.callout.monospaced().weight(.semibold))
                                .foregroundStyle(Color.notionInk)
                            Text(verbatim: CurrencyCatalog.displayName(homeCurrency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                        systemImage: "circle.righthalf.filled",
                        tint: .notionPurple
                    )
                }
            } header: {
                NotionSectionHeader("settings.section.general")
            }

            Section {
                Toggle(isOn: $reminderEnabled) {
                    settingsRowLabel(
                        titleKey: "settings.reminder.toggle",
                        systemImage: "bell.fill",
                        tint: .notionOrange
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
                            systemImage: "calendar",
                            tint: .notionPurple
                        )
                    }
                    .pickerStyle(.menu)

                    DatePicker(
                        selection: reminderTimeBinding,
                        displayedComponents: [.hourAndMinute]
                    ) {
                        settingsRowLabel(
                            titleKey: "settings.reminder.time",
                            systemImage: "clock.fill",
                            tint: .notionInkSecondary
                        )
                    }
                }
            } header: {
                NotionSectionHeader("settings.section.reminder")
            } footer: {
                Text("settings.reminder.footer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                        systemImage: "square.and.arrow.up",
                        tint: .notionBlue
                    )
                }
                .buttonStyle(.plain)

                Button {
                    beginCSVExport()
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.backup.exportCSV",
                        systemImage: "tablecells",
                        tint: .notionGreen
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isImporting = true
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.backup.import",
                        systemImage: "square.and.arrow.down",
                        tint: .notionTeal
                    )
                }
                .buttonStyle(.plain)
            } header: {
                NotionSectionHeader("settings.section.backup")
            } footer: {
                Text("settings.backup.footer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    isShowingFeatureTour = true
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.featureTour.show",
                        systemImage: "sparkles",
                        tint: .notionPurple
                    )
                }
                .buttonStyle(.plain)
            } header: {
                NotionSectionHeader("settings.section.help")
            } footer: {
                Text("settings.featureTour.footer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Text(verbatim: appVersion)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                } label: {
                    settingsRowLabel(
                        titleKey: "settings.about.version",
                        systemImage: "info.circle.fill",
                        tint: .notionInkSecondary
                    )
                }

                Link(destination: Self.repositoryURL) {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.about.sourceCode",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            tint: .notionInk
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Link(destination: Self.starURL) {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.about.star",
                            systemImage: "star.fill",
                            tint: .notionOrange
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Link(destination: Self.bugReportURL) {
                    HStack {
                        settingsRowLabel(
                            titleKey: "settings.about.bugReport",
                            systemImage: "ladybug.fill",
                            tint: .notionPink
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                NotionSectionHeader("settings.section.about")
            } footer: {
                Text("settings.about.footer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .glassListStyle()
        .navigationTitle("settings.title")
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
    }

    // MARK: - Helpers

    private func settingsRowLabel(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            GlyphBadge(systemName: systemImage, tint: tint, size: 28)
            Text(titleKey)
                .font(.body)
                .foregroundStyle(Color.notionInk)
        }
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
            let data = try BackupService.makeBackup(in: context)
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
            _ = try BackupService.restoreReplacing(from: data, context: context)
            resultMessage = "settings.backup.import.success"
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
                    .foregroundStyle(Color.notionInk)
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

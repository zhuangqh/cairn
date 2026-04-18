import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(LocalizationService.self) private var localization
    @Environment(\.modelContext) private var context

    @State private var exportDocument: BackupDocument?
    @State private var isExporting: Bool = false
    @State private var isImporting: Bool = false
    @State private var importConfirmation: Data?
    @State private var resultMessage: LocalizedStringKey?

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

                Section {
                    Button {
                        beginExport()
                    } label: {
                        Label {
                            Text("settings.backup.export")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label {
                            Text("settings.backup.import")
                        } icon: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                } header: {
                    Text("settings.section.backup")
                } footer: {
                    Text("settings.backup.footer")
                }
            }
            .navigationTitle("settings.title")
        }
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
        .confirmationDialog(
            "settings.backup.import.confirm.title",
            isPresented: .init(
                get: { importConfirmation != nil },
                set: { if !$0 { importConfirmation = nil } }
            ),
            titleVisibility: .visible
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
    }

    // MARK: - Export

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

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "cairn-backup-\(formatter.string(from: .now)).cairn"
    }

    // MARK: - Import

    private func loadImportCandidate(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            // Validate eagerly so we surface errors before the destructive confirm.
            _ = try BackupService.parse(data)
            importConfirmation = data
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
        } catch {
            resultMessage = "settings.backup.import.failure"
        }
    }
}

#Preview {
    SettingsView()
        .environment(LocalizationService())
        .modelContainer(PersistenceController.previewContainer())
}

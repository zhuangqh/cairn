import SwiftUI
import SwiftData

// Backup export / import actions for `SettingsView`. The state they drive
// and the file exporter / importer / alert presentations stay on the view
// itself, outside the settings form.

extension SettingsView {
    @MainActor
    func beginExport() {
        do {
            let data = try BackupService.makeBackup(in: context, homeCurrency: homeCurrency)
            exportDocument = BackupDocument(data: data)
            isExporting = true
        } catch {
            resultMessage = "settings.backup.export.failure"
        }
    }

    @MainActor
    func beginCSVExport() {
        do {
            let data = try BackupService.makeSnapshotCSV(in: context)
            csvExportDocument = CSVExportDocument(data: data)
            isExportingCSV = true
        } catch {
            resultMessage = "settings.backup.export.failure"
        }
    }

    /// `<stem>-yyyyMMdd-HHmm.<ext>`, stamped with the current local time.
    func defaultExportFilename(stem: String, fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "\(stem)-\(formatter.string(from: .now)).\(fileExtension)"
    }

    func loadImportCandidate(from url: URL) {
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
    func performRestore() {
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

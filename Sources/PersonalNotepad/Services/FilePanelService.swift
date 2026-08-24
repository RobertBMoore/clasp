import AppKit
import Foundation

@MainActor
enum FilePanelService {
    static func chooseExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Encrypted Vault"
        panel.nameFieldStringValue = "Clasp Vault Backup.pnvault-export"
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Encrypted Vault"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// AppKit begins security-scoped access for URLs returned by open and save
    /// panels. Balance that grant after the asynchronous file operation (or a
    /// cancelled import flow) has finished.
    static func releaseAccess(to url: URL) {
        if DistributionCapabilities.isAppStoreBuild {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

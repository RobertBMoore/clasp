import Foundation

enum AppPaths {
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Personal Notepad", isDirectory: true)
    }

    static var vaultDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Vault", isDirectory: true)
    }
}

import SwiftUI

struct SettingsView: View {
    @AppStorage(PreferenceKeys.appAppearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(PreferenceKeys.autoLockTimeout) private var autoLock = VaultAutoLockTimeout.tenMinutes.rawValue
    @AppStorage(PreferenceKeys.clipboardClearDelay) private var clipboardDelay = ClipboardClearDelay.thirtySeconds.rawValue

    var body: some View {
        TabView {
            Form {
                Section("Theme") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("System follows your Mac automatically. Light and Dark keep Clasp in the selected appearance.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Appearance", systemImage: AppIcon.Utility.appearance) }

            Form {
                Section("Automatic Locking") {
                    Picker("Lock Vault after", selection: $autoLock) {
                        ForEach(VaultAutoLockTimeout.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    if autoLock == VaultAutoLockTimeout.never.rawValue {
                        Label("Vault notes remain decrypted in memory until you lock manually or the system session changes.", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Vault", systemImage: AppIcon.Vault.destination) }

            Form {
                Section("Vault Capture") {
                    Picker("Clear captured clipboard after", selection: $clipboardDelay) {
                        ForEach(ClipboardClearDelay.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    if clipboardDelay == ClipboardClearDelay.never.rawValue {
                        Label("Captured Vault content remains on the clipboard until you clear or replace it.", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Clasp clears only the exact text or image it captured. Anything copied afterward is left alone, and clipboard history is never stored.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Clipboard", systemImage: AppIcon.Capture.clipboard) }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 290, idealHeight: 340)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .onChange(of: autoLock) { _, _ in VaultLockCoordinator.shared.noteActivity() }
    }
}

import SwiftUI

struct HelpView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var shortcutPreferences = GlobalHotKeyPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HelpSection(title: "Add Anything: Clasp or Vault", symbol: "square.and.arrow.down") {
                    ClipboardHelpFlow()
                    Text("Copy text, Markdown, a link, or an image. Press \(shortcutWords(.saveClipboardToInbox)) for a normal Inbox note or \(shortcutWords(.saveClipboardToVault)) for a secure Vault note. The menu-bar and Dock actions do the same thing.")
                    if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                        Text("For a one-step selection capture, press \(shortcutWords(.captureSelectionToInbox)) for a normal Inbox note or \(shortcutWords(.captureSelectionToVault)) for a secure Vault note. These direct-build actions request Accessibility only to issue Copy once.")
                    } else {
                        Text("For selected content, choose \(inboxService.title) or \(vaultService.title) from the source app’s Services menu. Clipboard shortcuts remain available for text, Markdown, links, and images without Accessibility access.")
                    }
                    Label("When enabled, safe clearing removes the captured value only if your clipboard has not changed. Anything copied afterward is left alone.", systemImage: "checkmark.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HelpSection(title: "Three easy ways", symbol: "hand.point.up.left") {
                    Text("1. Press \(shortcutWords(.quickCapturePrimary)) anywhere for Quick Capture.")
                    Text("   If it is already used, press \(shortcutWords(.quickCaptureFallback)).")
                    Text("2. Copy something, then press \(shortcutWords(.saveClipboardToInbox)) for Inbox or \(shortcutWords(.saveClipboardToVault)) for Vault.")
                    Text("3. Click Clasp in the menu bar or right-click its Dock icon for the same quick actions.")
                }

                HelpSection(title: "Feature Trigger Guide", symbol: "sparkles") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        trigger("Quick Capture", shortcutSymbols(.quickCapturePrimary), "Fallback: \(shortcutSymbols(.quickCaptureFallback))")
                        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                            trigger("Selected content to Inbox", shortcutSymbols(.captureSelectionToInbox), "Services: \(inboxService.title)")
                            trigger("Selected content to Vault", shortcutSymbols(.captureSelectionToVault), "Services: \(vaultService.title)")
                        } else {
                            trigger("Selected content to Inbox", "Default \(inboxService.defaultShortcut)", inboxService.title)
                            trigger("Selected content to Vault", "Default \(vaultService.defaultShortcut)", vaultService.title)
                        }
                        trigger("Copied content to Inbox", shortcutSymbols(.saveClipboardToInbox), "Menu bar or Dock")
                        trigger("Copied content to Vault", shortcutSymbols(.saveClipboardToVault), "Menu bar or Dock")
                        trigger("New note", "⌘N", "Creates in Vault when you are viewing Vault; otherwise uses Inbox")
                        trigger("Lock Vault", shortcutSymbols(.lockVault), "Menu bar, toolbar, or Dock")
                        trigger("Organize a note", "Right-click note", "Pin, archive, trash, restore")
                    }
                }

                HelpSection(title: "Optional shortcuts", symbol: "command") {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        shortcut("New note", "⌘N")
                        shortcut("New secure note", "⇧⌘N")
                        shortcut("Quick Capture", shortcutSymbols(.quickCapturePrimary))
                        shortcut("Quick Capture fallback", shortcutSymbols(.quickCaptureFallback))
                        shortcut("Copied content to Inbox", shortcutSymbols(.saveClipboardToInbox))
                        shortcut("Copied content to Vault", shortcutSymbols(.saveClipboardToVault))
                        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                            shortcut("Selected content to Inbox", shortcutSymbols(.captureSelectionToInbox))
                            shortcut("Selected content to Vault", shortcutSymbols(.captureSelectionToVault))
                        }
                        shortcut("Lock Vault", shortcutSymbols(.lockVault))
                    }
                }

                HelpSection(title: "Right-click Text, Images, or Links", symbol: "cursorarrow.click.2") {
                    Text("Choose Services › \(inboxService.title) for a normal Inbox note, or \(vaultService.title) for a secure encrypted Vault note. Content supplied by the source app is captured without Accessibility permission.")
                    if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                        Text("The one-step shortcuts are \(shortcutWords(.captureSelectionToInbox)) for Inbox and \(shortcutWords(.captureSelectionToVault)) for Vault. On first use, allow Clasp under Privacy & Security › Accessibility. Clasp uses that permission only to issue one Copy command for the current selection; it does not monitor your keyboard.")
                    } else {
                        Text("The App Store build intentionally uses macOS Services for selected content and never requests Accessibility permission. The shortcuts shown above are macOS defaults; you can change or remove them in Keyboard Settings.")
                    }
                    HStack {
                        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                            Button("Open Accessibility Settings") {
                                KeyboardSettingsOpener.openAccessibility()
                            }
                        }
                        Button("Open Service Settings") {
                            KeyboardSettingsOpener.open()
                        }
                    }
                    Group {
                        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                            Text("Clasp first tries to preserve the complete clipboard within strict size and item limits. If it cannot, the shortcut cancels before Copy. Otherwise it temporarily copies the selection, reads it once, and restores the preserved clipboard only if nothing newer has replaced it. The right-click Services remain the no-Accessibility fallback.")
                        } else {
                            Text("The source app supplies the selected content directly through macOS Services, so Clasp does not simulate Copy or replace your clipboard.")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Text("macOS and the source app control which Services appear. If an app does not expose Services for an image or link, copy it and use Clasp's menu-bar or Dock clipboard actions instead.")
                    Text("Inside Clasp, right-click any note to pin, archive, trash, or restore it.")
                }

                HelpSection(title: "Automatic Organization", symbol: AppIcon.Navigation.tag) {
                    Text("Clasp locally recognizes notes, links, images, code, checklists, and contact-like text. It adds high-confidence type tags, domains for links, task tags for checklists, and language tags for recognizable code.")
                    Text("Apple Vision recognizes text inside images on this Mac so it can be searched. No content is uploaded. Automatic tags remain visible and editable in the note.")
                    Label("Unlocked Vault notes also appear in All Notes with locked-document and shield icons. They disappear from All Notes and search as soon as the Vault locks.", systemImage: AppIcon.Vault.locked)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HelpSection(title: "Page / Markdown Editing", symbol: "textformat") {
                    Text("Use the Page / Markdown switch above a note. Page mode styles the same canonical Markdown source in place; Markdown mode exposes that source directly. Edits in either view update one portable note—there is no hidden rich-text copy.")
                    Text("Page mode recognizes common AI-generated Markdown: headings, bold, italic, strikethrough, links, bulleted and numbered lists, checklists, block quotes, inline and fenced code, and horizontal rules. Unknown syntax remains intact as source text.")
                    Text("Exceptionally large notes stay fully editable and source-exact. Page keeps the selected base typography while reducing live semantic decoration so typing and mode changes remain responsive.")
                    Text("Open Settings › Documents for Balanced, Compact, Spacious, and Technical presets, or adjust typeface, text size, line height, paragraph gap, and line length. These presentation settings stay outside the Markdown file.")
                    Text("Copied RTF and HTML are handled separately. Clasp keeps supported structure and safe web or email links, but sanitizes copied HTML by stripping active and resource-loading elements. The editor never executes embedded HTML or fetches remote content.")
                }

                HelpSection(title: "Appearance", symbol: AppIcon.Utility.appearance) {
                    Text("Open Clasp Settings and choose Appearance: System, Light, or Dark. System is the default and follows your Mac automatically; Light and Dark keep Clasp in the selected mode.")
                    Text("Page mode uses adaptive macOS colors and your Documents typography settings in every appearance.")
                }

                HelpSection(title: "Data locations", symbol: "folder") {
                    if DistributionCapabilities.isAppStoreBuild {
                        Text("Clasp keeps its data inside its protected App Sandbox container. This build includes a manifest intended to let macOS migrate an existing Personal Notepad data folder on first launch; release readiness still requires a controlled signed-sandbox migration and Vault-key custody test.")
                    }
                    Text("Regular Markdown and image attachments: \(dataRootPath)/Notes/")
                    Text("Encrypted Vault: \(dataRootPath)/Vault/")
                    Text("Back up the whole Personal Notepad folder. Clasp keeps this original data-directory name so existing notes remain available. Regular notes are plaintext; protect backups accordingly.")
                }

                HelpSection(title: "Vault backup and restore", symbol: "externaldrive") {
                    VaultBackupView(appState: appState)
                }

                HelpSection(title: "Security limits", symbol: "exclamationmark.shield") {
                    Text("Regular notes, image attachments, tags, and recognized image text are plaintext on disk. Vault text, images, tags, and recognized text are AES-GCM encrypted at rest, but an unlocked Vault exists in memory and cannot defend against malware or a person controlling your unlocked Mac. Clipboard managers may retain secrets. Prefer a dedicated password manager for credentials and recovery codes.")
                    if let privacyPolicyURL {
                        Link("Read Clasp’s Privacy Policy", destination: privacyPolicyURL)
                    }
                }

                HelpSection(title: "Onboarding", symbol: "sparkles") {
                    Button("Show Onboarding Again") {
                        OnboardingPreferences().reset()
                        openWindow(id: "onboarding")
                    }
                }
            }
            .padding(28)
            .textSelection(.enabled)
        }
        .navigationTitle("Clasp Help")
        .appStateErrorAlert(appState)
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        GridRow { Text(title); Text(keys).font(.body.monospaced()).foregroundStyle(.secondary) }
    }

    private var inboxService: MacOSCaptureServiceDescriptor {
        MacOSCaptureServiceDescriptor.all[0]
    }

    private var vaultService: MacOSCaptureServiceDescriptor {
        MacOSCaptureServiceDescriptor.all[1]
    }

    private func shortcutSymbols(_ action: GlobalHotKeyAction) -> String {
        shortcutPreferences.shortcut(for: action)?.symbolDisplayName ?? "Not set"
    }

    private func shortcutWords(_ action: GlobalHotKeyAction) -> String {
        shortcutPreferences.shortcut(for: action)?
            .displayName.replacingOccurrences(of: "-", with: "–") ?? "no shortcut"
    }

    private var dataRootPath: String {
        NSString(
            string: AppPaths.applicationSupportDirectory.path(percentEncoded: false)
        ).abbreviatingWithTildeInPath
    }

    private var privacyPolicyURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ClaspPrivacyPolicyURL") as? String,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }

    private func trigger(_ feature: String, _ primary: String, _ alternative: String) -> some View {
        GridRow {
            Text(feature).fontWeight(.medium)
            Text(primary).font(.body.monospaced()).foregroundStyle(.secondary)
            Text(alternative).foregroundStyle(.secondary)
        }
    }
}

private struct ClipboardHelpFlow: View {
    var body: some View {
        HStack(spacing: 10) {
            flowStep(symbol: AppIcon.Capture.clipboard, title: "1. Copy", detail: "Text, link, or image", tint: .blue)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            flowStep(symbol: "arrow.triangle.branch", title: "2. Choose", detail: "Clasp or Vault", tint: .orange)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            flowStep(symbol: "tag.fill", title: "3. Organized", detail: "Typed and tagged", tint: .green)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func flowStep(symbol: String, title: String, detail: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            Text(title).font(.callout.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

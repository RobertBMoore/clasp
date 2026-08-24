import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance
    case documents
    case shortcuts
    case vault
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .documents: "Documents"
        case .shortcuts: "Shortcuts & Capture"
        case .vault: "Vault"
        case .clipboard: "Clipboard"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: AppIcon.Utility.appearance
        case .documents: "doc.richtext"
        case .shortcuts: "keyboard"
        case .vault: AppIcon.Vault.destination
        case .clipboard: AppIcon.Capture.clipboard
        }
    }

    var subtitle: String {
        switch self {
        case .appearance:
            "Choose how Clasp looks across every window."
        case .documents:
            "Tune the reading experience without changing your Markdown."
        case .shortcuts:
            "See every capture route and choose the shortcuts that fit your Mac."
        case .vault:
            "Choose when decrypted Vault content locks again."
        case .clipboard:
            "Control safe clearing after a clipboard capture to Vault."
        }
    }
}

/// One fixed content envelope prevents the Settings window from resizing or
/// moving its controls when a tab, preset, or optional warning changes.
enum SettingsLayoutMetrics {
    static let fixedContentSize = CGSize(width: 850, height: 560)
    static let pagePadding: CGFloat = 24
    static let headerHeight: CGFloat = 52
    static let documentControlsWidth: CGFloat = 350
    static let documentColumnSpacing: CGFloat = 20
    static let simpleCardSize = CGSize(width: 620, height: 176)
    static let messageSlotHeight: CGFloat = 52
    static let presetDescriptionHeight: CGFloat = 36
    static let adjustmentStatusHeight: CGFloat = 18
    static let fontDescriptionHeight: CGFloat = 30
    static let metricRowHeight: CGFloat = 30
    static let shortcutFeedbackHeight: CGFloat = 48
    static let shortcutRowMinimumHeight: CGFloat = 124
    static let shortcutKeycapMinimumWidth: CGFloat = 110
    static let shortcutRecorderDefaultSize = CGSize(width: 460, height: 280)
    static let shortcutRecorderMessageMinimumHeight: CGFloat = 44

    static func contentSize(for pane: SettingsPane) -> CGSize {
        fixedContentSize
    }

    static var minimumDocumentPreviewWidth: CGFloat {
        fixedContentSize.width
            - (pagePadding * 2)
            - documentControlsWidth
            - documentColumnSpacing
    }
}

struct SettingsView: View {
    @State private var selectedPane = SettingsPane.appearance
    @AppStorage(PreferenceKeys.appAppearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(PreferenceKeys.autoLockTimeout) private var autoLock = VaultAutoLockTimeout.tenMinutes.rawValue
    @AppStorage(PreferenceKeys.clipboardClearDelay) private var clipboardDelay = ClipboardClearDelay.thirtySeconds.rawValue

    var body: some View {
        TabView(selection: $selectedPane) {
            appearancePage
                .tag(SettingsPane.appearance)
                .tabItem { Label(SettingsPane.appearance.title, systemImage: SettingsPane.appearance.systemImage) }

            DocumentSettingsView()
                .tag(SettingsPane.documents)
                .tabItem { Label(SettingsPane.documents.title, systemImage: SettingsPane.documents.systemImage) }

            ShortcutsCaptureSettingsView()
                .tag(SettingsPane.shortcuts)
                .tabItem { Label(SettingsPane.shortcuts.title, systemImage: SettingsPane.shortcuts.systemImage) }

            vaultPage
                .tag(SettingsPane.vault)
                .tabItem { Label(SettingsPane.vault.title, systemImage: SettingsPane.vault.systemImage) }

            clipboardPage
                .tag(SettingsPane.clipboard)
                .tabItem { Label(SettingsPane.clipboard.title, systemImage: SettingsPane.clipboard.systemImage) }
        }
        .frame(
            width: SettingsLayoutMetrics.contentSize(for: selectedPane).width,
            height: SettingsLayoutMetrics.contentSize(for: selectedPane).height
        )
        .onChange(of: autoLock) { _, _ in VaultLockCoordinator.shared.noteActivity() }
    }

    private var appearancePage: some View {
        SettingsTabPage(pane: .appearance) {
            SettingsSimpleCard(title: "App appearance", systemImage: AppIcon.Utility.appearance) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Theme")
                            .font(.body.weight(.medium))
                        Text("Applied to every Clasp window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)

                    Picker("Appearance", selection: appearanceBinding) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                    .accessibilityLabel("Appearance")
                }

                Divider()

                SettingsMessageSlot(systemImage: "circle.lefthalf.filled") {
                    Text("System follows your Mac automatically. Light and Dark keep Clasp in the selected appearance.")
                }
            }
        }
    }

    private var vaultPage: some View {
        SettingsTabPage(pane: .vault) {
            SettingsSimpleCard(title: "Automatic locking", systemImage: "lock.rotation") {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lock Vault after")
                            .font(.body.weight(.medium))
                        Text("The timer resets while you use Clasp")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)

                    Picker("Lock Vault after", selection: $autoLock) {
                        ForEach(VaultAutoLockTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .accessibilityLabel("Lock Vault after")
                }

                Divider()

                SettingsMessageSlot(
                    systemImage: autoLock == VaultAutoLockTimeout.never.rawValue
                        ? "exclamationmark.triangle.fill"
                        : "lock.fill",
                    isWarning: autoLock == VaultAutoLockTimeout.never.rawValue
                ) {
                    if autoLock == VaultAutoLockTimeout.never.rawValue {
                        Text("Vault notes remain decrypted in memory until you lock manually or the system session changes.")
                    } else {
                        Text("Clasp locks the Vault after the selected period of inactivity and when your Mac session changes.")
                    }
                }
            }
        }
    }

    private var clipboardPage: some View {
        SettingsTabPage(pane: .clipboard) {
            SettingsSimpleCard(title: "Vault capture", systemImage: AppIcon.Capture.clipboardToVault) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clear captured clipboard after")
                            .font(.body.weight(.medium))
                        Text("Only the exact captured value is eligible")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)

                    Picker("Clear captured clipboard after", selection: $clipboardDelay) {
                        ForEach(ClipboardClearDelay.allCases) { delay in
                            Text(delay.title).tag(delay.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .accessibilityLabel("Clear captured clipboard after")
                }

                Divider()

                SettingsMessageSlot(
                    systemImage: clipboardDelay == ClipboardClearDelay.never.rawValue
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.shield.fill",
                    isWarning: clipboardDelay == ClipboardClearDelay.never.rawValue
                ) {
                    if clipboardDelay == ClipboardClearDelay.never.rawValue {
                        Text("Captured Vault content remains on the clipboard until you clear or replace it.")
                    } else {
                        Text("Clasp clears only the value it captured. Anything copied afterward is left alone, and clipboard history is never stored.")
                    }
                }
            }
        }
    }

    /// Updates AppKit's single application appearance synchronously with the
    /// picker. All open windows, native lists, materials, and text views then
    /// transition together instead of waiting on independent scene rebuilds.
    private var appearanceBinding: Binding<String> {
        Binding(
            get: { (AppAppearance(rawValue: appearance) ?? .system).rawValue },
            set: { rawValue in
                let preference = AppAppearance(rawValue: rawValue) ?? .system
                AppAppearanceController.apply(preference)
                appearance = preference.rawValue
            }
        )
    }
}

struct SettingsTabPage<Content: View>: View {
    let pane: SettingsPane
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPageHeader(pane: pane)
                .frame(minHeight: SettingsLayoutMetrics.headerHeight)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(SettingsLayoutMetrics.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsPageHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.title3.weight(.semibold))
                Text(pane.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSimpleCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(18)
        .frame(
            width: SettingsLayoutMetrics.simpleCardSize.width,
            height: SettingsLayoutMetrics.simpleCardSize.height,
            alignment: .topLeading
        )
        .settingsCardSurface()
    }
}

private struct SettingsMessageSlot<Content: View>: View {
    let systemImage: String
    var isWarning = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 16)
                .accessibilityHidden(true)
            content
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: SettingsLayoutMetrics.messageSlotHeight, alignment: .topLeading)
    }
}

private struct DocumentSettingsView: View {
    @AppStorage(PreferenceKeys.documentStylePreset) private var presetRawValue = DocumentStylePreset.balanced.rawValue
    @AppStorage(PreferenceKeys.documentFontFamily) private var fontFamilyRawValue = DocumentStyle.balanced.fontFamily.rawValue
    @AppStorage(PreferenceKeys.documentBodyPointSize) private var bodyPointSize = DocumentStyle.balanced.bodyPointSize
    @AppStorage(PreferenceKeys.documentLineHeightMultiplier) private var lineHeightMultiplier = DocumentStyle.balanced.lineHeightMultiplier
    @AppStorage(PreferenceKeys.documentParagraphSpacing) private var paragraphSpacing = DocumentStyle.balanced.paragraphSpacing
    @AppStorage(PreferenceKeys.documentTargetCharactersPerLine) private var targetCharactersPerLine = DocumentStyle.balanced.targetCharactersPerLine

    var body: some View {
        SettingsTabPage(pane: .documents) {
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: SettingsLayoutMetrics.documentColumnSpacing) {
                    DocumentControlsPanel(
                        style: style,
                        selectedPreset: selectedPreset,
                        selectedFontFamily: selectedFontFamily,
                        preset: presetBinding,
                        fontFamily: fontFamilyBinding,
                        bodyPointSize: bodyPointSizeBinding,
                        lineHeight: lineHeightBinding,
                        paragraphSpacing: paragraphSpacingBinding,
                        targetCharacters: targetCharactersBinding,
                        restoreDefaults: { apply(.balanced) }
                    )
                    .frame(width: SettingsLayoutMetrics.documentControlsWidth)

                    DocumentStylePreview(style: style)
                        .frame(
                            minWidth: SettingsLayoutMetrics.minimumDocumentPreviewWidth,
                            minHeight: 420
                        )
                }
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
    }

    private var selectedPreset: DocumentStylePreset {
        DocumentStylePreset(rawValue: presetRawValue) ?? .balanced
    }

    private var selectedFontFamily: DocumentFontFamily {
        DocumentFontFamily(rawValue: fontFamilyRawValue) ?? selectedPreset.style.fontFamily
    }

    private var style: DocumentStyle {
        DocumentStyle(
            preset: selectedPreset,
            fontFamily: selectedFontFamily,
            bodyPointSize: bodyPointSize,
            lineHeightMultiplier: lineHeightMultiplier,
            paragraphSpacing: paragraphSpacing,
            targetCharactersPerLine: targetCharactersPerLine
        )
    }

    private var presetBinding: Binding<DocumentStylePreset> {
        Binding(
            get: { selectedPreset },
            set: { apply($0) }
        )
    }

    private var fontFamilyBinding: Binding<DocumentFontFamily> {
        Binding(
            get: { selectedFontFamily },
            set: { fontFamilyRawValue = $0.rawValue }
        )
    }

    private var bodyPointSizeBinding: Binding<Double> {
        clampedBinding($bodyPointSize, using: DocumentStyle.clampBodyPointSize)
    }

    private var lineHeightBinding: Binding<Double> {
        clampedBinding($lineHeightMultiplier, using: DocumentStyle.clampLineHeightMultiplier)
    }

    private var paragraphSpacingBinding: Binding<Double> {
        clampedBinding($paragraphSpacing, using: DocumentStyle.clampParagraphSpacing)
    }

    private var targetCharactersBinding: Binding<Double> {
        clampedBinding($targetCharactersPerLine, using: DocumentStyle.clampTargetCharactersPerLine)
    }

    private func clampedBinding(
        _ source: Binding<Double>,
        using clamp: @escaping (Double) -> Double
    ) -> Binding<Double> {
        Binding(
            get: { clamp(source.wrappedValue) },
            set: { source.wrappedValue = clamp($0) }
        )
    }

    private func apply(_ preset: DocumentStylePreset) {
        let value = preset.style
        presetRawValue = preset.rawValue
        fontFamilyRawValue = value.fontFamily.rawValue
        bodyPointSize = value.bodyPointSize
        lineHeightMultiplier = value.lineHeightMultiplier
        paragraphSpacing = value.paragraphSpacing
        targetCharactersPerLine = value.targetCharactersPerLine
    }
}

private struct DocumentControlsPanel: View {
    let style: DocumentStyle
    let selectedPreset: DocumentStylePreset
    let selectedFontFamily: DocumentFontFamily
    let preset: Binding<DocumentStylePreset>
    let fontFamily: Binding<DocumentFontFamily>
    let bodyPointSize: Binding<Double>
    let lineHeight: Binding<Double>
    let paragraphSpacing: Binding<Double>
    let targetCharacters: Binding<Double>
    let restoreDefaults: () -> Void

    private var isAdjustedFromPreset: Bool {
        style != selectedPreset.style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Reading style", systemImage: "textformat.size")
                .font(.headline)

            Picker("Reading preset", selection: preset) {
                ForEach(DocumentStylePreset.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Reading preset")

            Text(selectedPreset.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SettingsLayoutMetrics.presetDescriptionHeight,
                    alignment: .topLeading
                )

            Label("Adjusted from \(selectedPreset.title)", systemImage: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(isAdjustedFromPreset ? 1 : 0)
                .accessibilityHidden(!isAdjustedFromPreset)
                .frame(height: SettingsLayoutMetrics.adjustmentStatusHeight, alignment: .leading)

            Divider()

            HStack(spacing: 12) {
                Text("Typeface")
                    .frame(width: 96, alignment: .leading)

                Picker("Typeface", selection: fontFamily) {
                    ForEach(DocumentFontFamily.allCases) { family in
                        Text(family.title)
                            .font(Font(family.resolvedFont(ofSize: 13)))
                            .tag(family)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Document typeface")
            }
            .frame(minHeight: SettingsLayoutMetrics.metricRowHeight)

            Text(selectedFontFamily.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SettingsLayoutMetrics.fontDescriptionHeight,
                    alignment: .topLeading
                )

            Divider()

            DocumentMetricSlider(
                title: "Text size",
                value: bodyPointSize,
                range: DocumentStyle.bodyPointSizeRange,
                step: 1,
                formattedValue: "\(style.bodyPointSize.formatted(.number.precision(.fractionLength(0)))) pt",
                accessibilityValue: "\(style.bodyPointSize.formatted(.number.precision(.fractionLength(0)))) points"
            )

            DocumentMetricSlider(
                title: "Line height",
                value: lineHeight,
                range: DocumentStyle.lineHeightMultiplierRange,
                step: 0.05,
                formattedValue: "\(style.lineHeightMultiplier.formatted(.number.precision(.fractionLength(2))))×",
                accessibilityValue: "\(style.lineHeightMultiplier.formatted(.number.precision(.fractionLength(2)))) times text size"
            )

            DocumentMetricSlider(
                title: "Paragraph gap",
                value: paragraphSpacing,
                range: DocumentStyle.paragraphSpacingRange,
                step: 1,
                formattedValue: "\(style.paragraphSpacing.formatted(.number.precision(.fractionLength(0)))) pt",
                accessibilityValue: "\(style.paragraphSpacing.formatted(.number.precision(.fractionLength(0)))) points"
            )

            DocumentMetricSlider(
                title: "Line length",
                value: targetCharacters,
                range: DocumentStyle.targetCharactersPerLineRange,
                step: 1,
                formattedValue: "\(style.targetCharactersPerLine.formatted(.number.precision(.fractionLength(0)))) chars",
                accessibilityValue: "\(style.targetCharactersPerLine.formatted(.number.precision(.fractionLength(0)))) characters"
            )

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("Restore Defaults", action: restoreDefaults)
                    .disabled(style == .balanced)
                    .help("Restore the Balanced document presentation")

                Spacer(minLength: 8)

                Label("Markdown unchanged", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .settingsCardSurface()
    }
}

private struct DocumentMetricSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let formattedValue: String
    let accessibilityValue: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 96, alignment: .leading)

            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)

            Text(formattedValue)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .frame(minHeight: SettingsLayoutMetrics.metricRowHeight)
    }
}

private struct DocumentStylePreview: View {
    let style: DocumentStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Live preview", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)

                Spacer()

                Text(style.fontFamily.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.10), in: Capsule())
            }

            DocumentPreviewCanvas(style: style)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                PreviewMetric(
                    title: "Size",
                    value: "\(style.bodyPointSize.formatted(.number.precision(.fractionLength(0)))) pt"
                )
                Divider().frame(height: 28)
                PreviewMetric(
                    title: "Leading",
                    value: "\(style.lineHeightMultiplier.formatted(.number.precision(.fractionLength(2))))×"
                )
                Divider().frame(height: 28)
                PreviewMetric(
                    title: "Measure",
                    value: "\(style.targetCharactersPerLine.formatted(.number.precision(.fractionLength(0)))) ch"
                )
            }
            .frame(height: 34)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .settingsCardSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live document style preview")
    }
}

private struct DocumentPreviewCanvas: View {
    let style: DocumentStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.18))

            DocumentPreviewPaper(style: style)
                .padding(12)
        }
        .clipped()
    }
}

private struct DocumentPreviewPaper: View {
    let style: DocumentStyle

    private var bodySize: CGFloat {
        CGFloat((style.bodyPointSize * 0.76).clamped(to: 12 ... 19))
    }

    private var headingSize: CGFloat {
        bodySize * 1.48
    }

    private var lineSpacing: CGFloat {
        CGFloat((style.lineSpacing * 0.55).clamped(to: 2 ... 10))
    }

    private var paragraphSpacing: CGFloat {
        CGFloat((style.paragraphSpacing * 0.55).clamped(to: 5 ... 14))
    }

    private var measureWidth: CGFloat {
        let progress = (style.targetCharactersPerLine - DocumentStyle.targetCharactersPerLineRange.lowerBound)
            / (DocumentStyle.targetCharactersPerLineRange.upperBound - DocumentStyle.targetCharactersPerLineRange.lowerBound)
        return CGFloat(225 + (progress * 105))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CLASP NOTE")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            Text("A calmer place to think")
                .font(previewFont(size: headingSize, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, paragraphSpacing)

            Text("Good reading design should disappear. Comfortable spacing and a clear measure keep the ideas in view.")
                .font(previewFont(size: bodySize))
                .lineSpacing(lineSpacing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, paragraphSpacing)

            HStack(alignment: .top, spacing: 8) {
                Capsule()
                    .fill(.tint)
                    .frame(width: 3, height: max(34, bodySize * 2.4))
                    .accessibilityHidden(true)
                Text("Presentation changes here; the portable Markdown stays exactly as written.")
                    .font(previewFont(size: max(11, bodySize - 1)))
                    .foregroundStyle(.secondary)
                    .lineSpacing(max(1, lineSpacing - 1))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, paragraphSpacing)

            Label("One source, beautifully presented", systemImage: "checkmark.circle.fill")
                .font(previewFont(size: max(11, bodySize - 1), weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: measureWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.separator.opacity(0.58), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func previewFont(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(style.fontFamily.resolvedFont(ofSize: size, weight: weight))
    }
}

private struct PreviewMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func settingsCardSurface() -> some View {
        background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

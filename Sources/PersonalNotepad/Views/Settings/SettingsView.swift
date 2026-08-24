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

            DocumentSettingsView()
                .tabItem { Label("Documents", systemImage: "doc.richtext") }

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
        .frame(minWidth: 680, idealWidth: 780, minHeight: 470, idealHeight: 550)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .onChange(of: autoLock) { _, _ in VaultLockCoordinator.shared.noteActivity() }
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
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    controls
                        .frame(minWidth: 300, idealWidth: 330, maxWidth: 360)
                    DocumentStylePreview(style: style)
                        .frame(minWidth: 300, maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 18) {
                    controls
                    DocumentStylePreview(style: style)
                }
            }
            .padding(20)
        }
        .accessibilityLabel("Document appearance settings")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Reading Preset") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Preset", selection: presetBinding) {
                        ForEach(DocumentStylePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }

                    Text(selectedPreset.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if style != selectedPreset.style {
                        Label("Adjusted from \(selectedPreset.title)", systemImage: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Fine Tuning") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 11) {
                    GridRow {
                        Text("Typeface")
                        Picker("Typeface", selection: fontFamilyBinding) {
                            ForEach(DocumentFontFamily.allCases) { family in
                                Text(family.title).tag(family)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Document typeface")
                    }

                    GridRow {
                        Text("Text size")
                        Stepper(value: bodyPointSizeBinding, in: DocumentStyle.bodyPointSizeRange, step: 1) {
                            Text("\(style.bodyPointSize, specifier: "%.0f") pt")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .accessibilityLabel("Body text size")
                        .accessibilityValue("\(style.bodyPointSize, specifier: "%.0f") points")
                    }

                    GridRow {
                        Text("Line height")
                        HStack(spacing: 9) {
                            Slider(
                                value: lineHeightBinding,
                                in: DocumentStyle.lineHeightMultiplierRange,
                                step: 0.05
                            )
                            Text("\(style.lineHeightMultiplier, specifier: "%.2f")×")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Line height")
                        .accessibilityValue("\(style.lineHeightMultiplier, specifier: "%.2f") times text size")
                    }

                    GridRow {
                        Text("Paragraph gap")
                        Stepper(value: paragraphSpacingBinding, in: DocumentStyle.paragraphSpacingRange, step: 1) {
                            Text("\(style.paragraphSpacing, specifier: "%.0f") pt")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .accessibilityLabel("Paragraph spacing")
                        .accessibilityValue("\(style.paragraphSpacing, specifier: "%.0f") points")
                    }

                    GridRow {
                        Text("Line length")
                        Stepper(
                            value: targetCharactersBinding,
                            in: DocumentStyle.targetCharactersPerLineRange,
                            step: 1
                        ) {
                            Text("\(style.targetCharactersPerLine, specifier: "%.0f") characters")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .accessibilityLabel("Target line length")
                        .accessibilityValue("\(style.targetCharactersPerLine, specifier: "%.0f") characters")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Button("Restore Balanced Defaults") {
                    apply(.balanced)
                }
                .help("Reset only document presentation settings")

                Spacer()

                Text("Markdown stays unchanged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func clampedBinding(_ source: Binding<Double>, using clamp: @escaping (Double) -> Double) -> Binding<Double> {
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

private struct DocumentStylePreview: View {
    let style: DocumentStyle

    var body: some View {
        GroupBox("Live Preview") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("A calmer place to think")
                        .font(previewFont(size: style.bodyPointSize * 1.65, weight: .semibold))
                        .padding(.bottom, CGFloat(style.paragraphSpacing * 0.8))

                    Text("Good reading design should disappear. A comfortable measure, generous line height, and clear hierarchy help the ideas stay in view.")
                        .font(previewFont(size: style.bodyPointSize))
                        .lineSpacing(style.lineSpacing)
                        .padding(.bottom, CGFloat(style.paragraphSpacing))

                    HStack(alignment: .top, spacing: 10) {
                        Capsule()
                            .fill(.tint)
                            .frame(width: 3)
                            .accessibilityHidden(true)
                        Text("Clasp changes the presentation, never the portable Markdown underneath it.")
                            .font(previewFont(size: style.bodyPointSize))
                            .foregroundStyle(.secondary)
                            .lineSpacing(style.lineSpacing)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.bottom, CGFloat(style.paragraphSpacing))

                    VStack(alignment: .leading, spacing: 7) {
                        Label("One portable source", systemImage: "checkmark.square.fill")
                        Label("Two beautiful views", systemImage: "square")
                    }
                        .font(previewFont(size: max(14, style.bodyPointSize - 1)))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                }
                .frame(maxWidth: previewContentWidth, alignment: .leading)
                .padding(.horizontal, min(style.pageHorizontalPadding * 0.55, 38))
                .padding(.vertical, 32)
                .background(.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.separator.opacity(0.65), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
                .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 330, maxHeight: 430)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live document style preview")
    }

    private var previewContentWidth: CGFloat {
        min(410, max(260, style.maxPageWidth * 0.52))
    }

    private func previewFont(size: Double, weight: Font.Weight = .regular) -> Font {
        switch style.fontFamily {
        case .system:
            .system(size: CGFloat(size), weight: weight)
        case .serif:
            .system(size: CGFloat(size), weight: weight, design: .serif)
        case .rounded:
            .system(size: CGFloat(size), weight: weight, design: .rounded)
        case .monospaced:
            .system(size: CGFloat(size), weight: weight, design: .monospaced)
        }
    }
}

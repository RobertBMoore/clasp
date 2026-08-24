import AppKit
import Foundation

enum DocumentFontFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case serif
    case rounded
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "SF Pro"
        case .serif: "New York"
        case .rounded: "SF Pro Rounded"
        case .monospaced: "SF Mono"
        }
    }

    var detail: String {
        switch self {
        case .system: "Apple's clear, familiar system sans serif."
        case .serif: "Apple's system serif for comfortable long-form reading."
        case .rounded: "A softer system face for personal and informal notes."
        case .monospaced: "Apple's fixed-width system face for technical text."
        }
    }

    /// Maps every user-facing choice to an AppKit system design. Clasp never
    /// accepts or persists arbitrary font names, so a missing or renamed font
    /// cannot leave documents unreadable after a macOS update.
    @MainActor
    var systemDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }

    /// Resolves the current macOS implementation of the selected system family.
    /// The fallback deliberately remains a system font at the requested size
    /// and weight instead of reaching for a hard-coded PostScript name.
    @MainActor
    func resolvedFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard systemDesign != .default,
              let descriptor = base.fontDescriptor.withDesign(systemDesign),
              let font = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return font
    }
}

enum DocumentStylePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced
    case compact
    case spacious
    case technical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .compact: "Compact"
        case .spacious: "Spacious"
        case .technical: "Technical"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "A calm 68-character reading measure for most documents."
        case .compact: "Fits more reference material on screen without becoming dense."
        case .spacious: "Larger serif text and a narrow measure for unhurried reading."
        case .technical: "Monospaced text and a stable measure for code-heavy notes."
        }
    }

    var style: DocumentStyle {
        switch self {
        case .balanced: .balanced
        case .compact: .compact
        case .spacious: .spacious
        case .technical: .technical
        }
    }
}

/// Presentation-only settings for the Markdown-backed editor.
///
/// These values never belong to `Note` and are never serialized into a Markdown
/// file. The initializer clamps every externally supplied value so corrupted or
/// manually edited defaults cannot create an unusable document surface.
struct DocumentStyle: Codable, Equatable, Sendable {
    static let bodyPointSizeRange = 14.0 ... 28.0
    static let lineHeightMultiplierRange = 1.25 ... 2.0
    static let paragraphSpacingRange = 4.0 ... 32.0
    static let targetCharactersPerLineRange = 45.0 ... 90.0

    let preset: DocumentStylePreset
    let fontFamily: DocumentFontFamily
    let bodyPointSize: Double
    let lineHeightMultiplier: Double
    let paragraphSpacing: Double
    let targetCharactersPerLine: Double

    static let balanced = DocumentStyle(
        preset: .balanced,
        fontFamily: .system,
        bodyPointSize: 18,
        lineHeightMultiplier: 1.55,
        paragraphSpacing: 12,
        targetCharactersPerLine: 68
    )

    static let compact = DocumentStyle(
        preset: .compact,
        fontFamily: .system,
        bodyPointSize: 16,
        lineHeightMultiplier: 1.4,
        paragraphSpacing: 8,
        targetCharactersPerLine: 76
    )

    static let spacious = DocumentStyle(
        preset: .spacious,
        fontFamily: .serif,
        bodyPointSize: 20,
        lineHeightMultiplier: 1.75,
        paragraphSpacing: 16,
        targetCharactersPerLine: 56
    )

    static let technical = DocumentStyle(
        preset: .technical,
        fontFamily: .monospaced,
        bodyPointSize: 16,
        lineHeightMultiplier: 1.5,
        paragraphSpacing: 10,
        targetCharactersPerLine: 72
    )

    static let appDefault = balanced

    init(
        preset: DocumentStylePreset,
        fontFamily: DocumentFontFamily,
        bodyPointSize: Double,
        lineHeightMultiplier: Double,
        paragraphSpacing: Double,
        targetCharactersPerLine: Double
    ) {
        self.preset = preset
        self.fontFamily = fontFamily
        self.bodyPointSize = Self.clampBodyPointSize(bodyPointSize)
        self.lineHeightMultiplier = Self.clampLineHeightMultiplier(lineHeightMultiplier)
        self.paragraphSpacing = Self.clampParagraphSpacing(paragraphSpacing)
        self.targetCharactersPerLine = Self.clampTargetCharactersPerLine(targetCharactersPerLine)
    }

    init(preset: DocumentStylePreset) {
        self = preset.style
    }

    func applying(_ preset: DocumentStylePreset) -> DocumentStyle {
        DocumentStyle(preset: preset)
    }

    static func clampBodyPointSize(_ value: Double) -> Double {
        guard value.isFinite else { return 18 }
        return value.clamped(to: bodyPointSizeRange)
    }

    static func clampLineHeightMultiplier(_ value: Double) -> Double {
        guard value.isFinite else { return 1.55 }
        return value.clamped(to: lineHeightMultiplierRange)
    }

    static func clampParagraphSpacing(_ value: Double) -> Double {
        guard value.isFinite else { return 12 }
        return value.clamped(to: paragraphSpacingRange)
    }

    static func clampTargetCharactersPerLine(_ value: Double) -> Double {
        guard value.isFinite else { return 68 }
        return value.clamped(to: targetCharactersPerLineRange)
    }

    /// Horizontal breathing room is deliberately independent from the source
    /// Markdown. Larger reading type receives slightly more page margin.
    var pageHorizontalPadding: CGFloat {
        CGFloat((bodyPointSize * 3.1).clamped(to: 44 ... 72))
    }

    /// Estimates a readable continuous-page width from the selected measure.
    /// The editor may fit this down responsively, but should not expand past it.
    var maxPageWidth: CGFloat {
        let widthFactor = fontFamily == .monospaced ? 0.61 : 0.52
        let textWidth = targetCharactersPerLine * bodyPointSize * widthFactor
        return CGFloat((textWidth + Double(pageHorizontalPadding * 2)).clamped(to: 620 ... 820))
    }

    var lineSpacing: CGFloat {
        CGFloat(bodyPointSize * (lineHeightMultiplier - 1))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

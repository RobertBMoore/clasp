import Foundation
import XCTest
@testable import PersonalNotepad

@MainActor
final class DocumentStyleTests: XCTestCase {
    func testBalancedIsTheApplicationDefault() {
        assertStyle(
            .balanced,
            preset: .balanced,
            family: .system,
            size: 18,
            lineHeight: 1.55,
            paragraphSpacing: 12,
            charactersPerLine: 68
        )
        XCTAssertEqual(DocumentStyle.appDefault, .balanced)
        XCTAssertEqual(DocumentStyle(preset: .balanced), .balanced)
        XCTAssertEqual(DocumentStylePreset.balanced.style, .balanced)
    }

    func testCompactSpaciousAndTechnicalDefaults() {
        assertStyle(
            .compact,
            preset: .compact,
            family: .system,
            size: 16,
            lineHeight: 1.4,
            paragraphSpacing: 8,
            charactersPerLine: 76
        )
        assertStyle(
            .spacious,
            preset: .spacious,
            family: .serif,
            size: 20,
            lineHeight: 1.75,
            paragraphSpacing: 16,
            charactersPerLine: 56
        )
        assertStyle(
            .technical,
            preset: .technical,
            family: .monospaced,
            size: 16,
            lineHeight: 1.5,
            paragraphSpacing: 10,
            charactersPerLine: 72
        )

        for preset in DocumentStylePreset.allCases {
            XCTAssertEqual(DocumentStyle(preset: preset), preset.style)
        }
    }

    func testExternallySuppliedValuesClampToSupportedBounds() {
        let belowMinimum = DocumentStyle(
            preset: .balanced,
            fontFamily: .rounded,
            bodyPointSize: -100,
            lineHeightMultiplier: -100,
            paragraphSpacing: -100,
            targetCharactersPerLine: -100
        )
        XCTAssertEqual(belowMinimum.bodyPointSize, DocumentStyle.bodyPointSizeRange.lowerBound)
        XCTAssertEqual(
            belowMinimum.lineHeightMultiplier,
            DocumentStyle.lineHeightMultiplierRange.lowerBound
        )
        XCTAssertEqual(
            belowMinimum.paragraphSpacing,
            DocumentStyle.paragraphSpacingRange.lowerBound
        )
        XCTAssertEqual(
            belowMinimum.targetCharactersPerLine,
            DocumentStyle.targetCharactersPerLineRange.lowerBound
        )

        let aboveMaximum = DocumentStyle(
            preset: .technical,
            fontFamily: .monospaced,
            bodyPointSize: 100,
            lineHeightMultiplier: 100,
            paragraphSpacing: 100,
            targetCharactersPerLine: 100
        )
        XCTAssertEqual(aboveMaximum.bodyPointSize, DocumentStyle.bodyPointSizeRange.upperBound)
        XCTAssertEqual(
            aboveMaximum.lineHeightMultiplier,
            DocumentStyle.lineHeightMultiplierRange.upperBound
        )
        XCTAssertEqual(
            aboveMaximum.paragraphSpacing,
            DocumentStyle.paragraphSpacingRange.upperBound
        )
        XCTAssertEqual(
            aboveMaximum.targetCharactersPerLine,
            DocumentStyle.targetCharactersPerLineRange.upperBound
        )

        XCTAssertEqual(DocumentStyle.clampBodyPointSize(17), 17)
        XCTAssertEqual(DocumentStyle.clampLineHeightMultiplier(1.6), 1.6)
        XCTAssertEqual(DocumentStyle.clampParagraphSpacing(14), 14)
        XCTAssertEqual(DocumentStyle.clampTargetCharactersPerLine(64), 64)

        let nonFinite = DocumentStyle(
            preset: .compact,
            fontFamily: .rounded,
            bodyPointSize: .nan,
            lineHeightMultiplier: .infinity,
            paragraphSpacing: -.infinity,
            targetCharactersPerLine: .nan
        )
        XCTAssertEqual(nonFinite.bodyPointSize, DocumentStyle.balanced.bodyPointSize)
        XCTAssertEqual(
            nonFinite.lineHeightMultiplier,
            DocumentStyle.balanced.lineHeightMultiplier
        )
        XCTAssertEqual(nonFinite.paragraphSpacing, DocumentStyle.balanced.paragraphSpacing)
        XCTAssertEqual(
            nonFinite.targetCharactersPerLine,
            DocumentStyle.balanced.targetCharactersPerLine
        )
    }

    func testApplyingPresetReplacesEveryPresentationValue() {
        let custom = DocumentStyle(
            preset: .compact,
            fontFamily: .rounded,
            bodyPointSize: 23,
            lineHeightMultiplier: 1.82,
            paragraphSpacing: 21,
            targetCharactersPerLine: 61
        )

        for preset in DocumentStylePreset.allCases {
            XCTAssertEqual(custom.applying(preset), preset.style)
        }
    }

    func testPreferencePresetApplicationAndResetAreDeterministic() throws {
        let suite = "DocumentStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DocumentStylePreferences.load(from: defaults), .appDefault)

        for preset in DocumentStylePreset.allCases {
            DocumentStylePreferences.apply(preset, in: defaults)
            XCTAssertEqual(DocumentStylePreferences.load(from: defaults), preset.style)
        }

        DocumentStylePreferences.reset(in: defaults)
        XCTAssertEqual(DocumentStylePreferences.load(from: defaults), .appDefault)
    }

    func testPresetPreferencesUseSeparateKeysAndDoNotEnterNoteContent() throws {
        let suite = "DocumentStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let markdown = """
        # Readable source

        **Formatting remains Markdown.**
        """
        let note = Note(title: "Readable source", body: markdown)

        DocumentStylePreferences.store(.spacious, in: defaults)
        defaults.set(AppAppearance.dark.rawValue, forKey: PreferenceKeys.appAppearance)

        XCTAssertEqual(DocumentStylePreferences.load(from: defaults), .spacious)
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.documentStylePreset), "spacious")
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.documentFontFamily), "serif")
        XCTAssertNotNil(defaults.object(forKey: PreferenceKeys.documentBodyPointSize))
        XCTAssertNotNil(defaults.object(forKey: PreferenceKeys.documentLineHeightMultiplier))
        XCTAssertNotNil(defaults.object(forKey: PreferenceKeys.documentParagraphSpacing))
        XCTAssertNotNil(defaults.object(forKey: PreferenceKeys.documentTargetCharactersPerLine))
        XCTAssertNil(defaults.object(forKey: "documentStyle"))
        XCTAssertNil(defaults.object(forKey: "markdown"))

        let encodedNote = try JSONEncoder().encode(note)
        let noteJSON = try XCTUnwrap(String(data: encodedNote, encoding: .utf8))
        let decodedNote = try JSONDecoder().decode(Note.self, from: encodedNote)

        XCTAssertEqual(note.body, markdown)
        XCTAssertEqual(decodedNote.body, markdown)
        XCTAssertFalse(noteJSON.contains("documentStyle"))
        XCTAssertFalse(noteJSON.contains("bodyPointSize"))
        XCTAssertFalse(noteJSON.contains("appAppearance"))
    }

    func testCorruptStoredValuesAreClampedWithoutChangingPresetIdentity() throws {
        let suite = "DocumentStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(DocumentStylePreset.technical.rawValue, forKey: PreferenceKeys.documentStylePreset)
        defaults.set(DocumentFontFamily.rounded.rawValue, forKey: PreferenceKeys.documentFontFamily)
        defaults.set(-1_000.0, forKey: PreferenceKeys.documentBodyPointSize)
        defaults.set(1_000.0, forKey: PreferenceKeys.documentLineHeightMultiplier)
        defaults.set(-1_000.0, forKey: PreferenceKeys.documentParagraphSpacing)
        defaults.set(1_000.0, forKey: PreferenceKeys.documentTargetCharactersPerLine)

        let loaded = DocumentStylePreferences.load(from: defaults)

        XCTAssertEqual(loaded.preset, .technical)
        XCTAssertEqual(loaded.fontFamily, .rounded)
        XCTAssertEqual(loaded.bodyPointSize, DocumentStyle.bodyPointSizeRange.lowerBound)
        XCTAssertEqual(
            loaded.lineHeightMultiplier,
            DocumentStyle.lineHeightMultiplierRange.upperBound
        )
        XCTAssertEqual(loaded.paragraphSpacing, DocumentStyle.paragraphSpacingRange.lowerBound)
        XCTAssertEqual(
            loaded.targetCharactersPerLine,
            DocumentStyle.targetCharactersPerLineRange.upperBound
        )
    }

    private func assertStyle(
        _ style: DocumentStyle,
        preset: DocumentStylePreset,
        family: DocumentFontFamily,
        size: Double,
        lineHeight: Double,
        paragraphSpacing: Double,
        charactersPerLine: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(style.preset, preset, file: file, line: line)
        XCTAssertEqual(style.fontFamily, family, file: file, line: line)
        XCTAssertEqual(style.bodyPointSize, size, file: file, line: line)
        XCTAssertEqual(style.lineHeightMultiplier, lineHeight, file: file, line: line)
        XCTAssertEqual(style.paragraphSpacing, paragraphSpacing, file: file, line: line)
        XCTAssertEqual(style.targetCharactersPerLine, charactersPerLine, file: file, line: line)
    }
}

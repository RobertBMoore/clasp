#if CLASP_VISUAL_QA
import Foundation

@MainActor
final class VisualQAClipboardClient: ClipboardClient {
    private var snapshot: ClipboardSnapshot? = ClipboardSnapshot(
        value: "Synthetic clipboard capture for visual QA",
        changeCount: 1
    )

    func readContent() -> ClipboardSnapshot? { snapshot }
    func currentSnapshot() -> ClipboardSnapshot? { snapshot }
    func clear() { snapshot = nil }
}

/// Synthetic, memory-only data used exclusively by the separately bundled
/// visual-QA app. Nothing in this file is compiled into local, direct, or App
/// Store builds.
private enum VisualQAData {
    static let regularNotes: [Note] = {
        let now = Date()
        let sampleImage = Bundle.main.url(forResource: "VisualQA-Sample", withExtension: "png")
            .flatMap { try? Data(contentsOf: $0) }

        return [
            Note(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                title: "Launch checklist",
                body: """
                # Launch checklist

                - [x] Review the welcome flow
                - [x] Verify keyboard shortcuts
                - [ ] Capture final App Store screenshots

                **Focus:** keep every interaction calm, clear, and unmistakably Mac-native.
                """,
                tags: ["launch", "today"],
                isPinned: true,
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-420),
                contentType: .checklist
            ),
            Note(
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                title: "Design review notes",
                body: """
                ## Design review notes

                The three-column layout keeps navigation, context, and writing visible at once. Toolbar actions use familiar macOS placement and language.

                Next pass: confirm compact-width behavior and VoiceOver labels.
                """,
                tags: ["design", "review"],
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-3_600)
            ),
            Note(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                title: "App Store submission guide",
                body: """
                App Store submission guide

                https://developer.apple.com/app-store/submitting/

                Keep release notes concise and verify the exact signed artifact before upload.
                """,
                tags: ["launch", "reference"],
                isInInbox: false,
                createdAt: now.addingTimeInterval(-259_200),
                updatedAt: now.addingTimeInterval(-7_200),
                contentType: .link
            ),
            Note(
                id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
                title: "Clasp icon study",
                body: "A focused visual study for the Clasp app icon and its friendly macOS presence.",
                tags: ["design", "visual"],
                isInInbox: false,
                createdAt: now.addingTimeInterval(-345_600),
                updatedAt: now.addingTimeInterval(-10_800),
                contentType: .image,
                attachments: sampleImage.map { [NoteAttachment(data: $0)] } ?? [],
                extractedText: "Clasp"
            ),
            Note(
                id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
                title: "Release coordinator",
                body: "Release coordinator\nhello@example.com\nConfirm review timing before the public launch.",
                tags: ["launch", "people"],
                isArchived: true,
                isInInbox: false,
                createdAt: now.addingTimeInterval(-432_000),
                updatedAt: now.addingTimeInterval(-86_400),
                contentType: .contact
            ),
            Note(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
                title: "Earlier screenshot notes",
                body: "Superseded layout observations retained here for recovery testing.",
                tags: ["archive"],
                isInInbox: false,
                trashedAt: now.addingTimeInterval(-43_200),
                createdAt: now.addingTimeInterval(-518_400),
                updatedAt: now.addingTimeInterval(-43_200)
            )
        ]
    }()

    static let vaultNotes: [Note] = {
        let now = Date()
        return [
            Note(
                id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
                title: "Private launch notes",
                body: """
                # Private launch notes

                Keep account-holder tasks and final release timing in the encrypted Vault.

                - Confirm agreements
                - Review export compliance
                - Approve the exact build
                """,
                tags: ["launch", "private"],
                isPinned: true,
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-1_800)
            ),
            Note(
                id: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
                title: "Recovery rehearsal",
                body: "Encrypted export verified with a separately stored synthetic recovery key.",
                tags: ["backup", "private"],
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-14_400)
            )
        ]
    }()
}

actor VisualQARegularNoteStore: RegularNoteStoring {
    private var notes = VisualQAData.regularNotes

    func load() -> [Note] { notes.sorted { $0.updatedAt > $1.updatedAt } }

    func save(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        notes.append(note)
    }

    func permanentlyDelete(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    func rebuildIndex() -> [Note] { notes.sorted { $0.updatedAt > $1.updatedAt } }
}

actor VisualQAVaultStore: VaultStoring {
    private var notes = VisualQAData.vaultNotes

    func isConfigured() -> Bool { true }
    func setup() -> [Note] { notes }
    func unlock() -> [Note] { notes.sorted { $0.updatedAt > $1.updatedAt } }
    func save(_ notes: [Note]) { self.notes = notes }
    func lock() {}

    func export(notes: [Note]) throws -> (data: Data, recoveryKey: RecoveryKey) {
        let recoveryKey = RecoveryKey()
        let encoder = configuredEncoder()
        let plaintext = try encoder.encode(VaultPayload(notes: notes))
        let envelope = VaultExport(ciphertext: try VaultCrypto.encrypt(plaintext, using: recoveryKey.symmetricKey))
        return (try encoder.encode(envelope), recoveryKey)
    }

    func importVault(_ data: Data, recoveryKey: RecoveryKey) throws -> [Note] {
        let decoder = configuredDecoder()
        let envelope = try decoder.decode(VaultExport.self, from: data)
        guard envelope.formatVersion == VaultExport.currentVersion else {
            throw VaultCryptoError.unsupportedVersion
        }
        let plaintext = try VaultCrypto.decrypt(envelope.ciphertext, using: recoveryKey.symmetricKey)
        notes = try decoder.decode(VaultPayload.self, from: plaintext).notes
        return notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func configuredEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
#endif

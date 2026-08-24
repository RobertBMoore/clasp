import AppKit
import Foundation
import Observation

protocol ContentClassifying: Sendable {
    func classify(_ content: CapturedContent) async -> ClassifiedCapture
}

extension ContentClassifier: ContentClassifying {}

@MainActor
@Observable
final class AppState {
    private(set) var regularNotes: [Note] = []
    private(set) var vaultNotes: [Note]?
    private(set) var isLoading = true
    var statusMessage: String?
    var presentedError: String?
    var quickCaptureSeed = ""
    var quickCaptureDestination: CaptureDestination = .inbox

    private let regularStore: any RegularNoteStoring
    private let vaultStore: any VaultStoring
    private let clipboard: ClipboardService
    private let classifier: any ContentClassifying
    private let vaultImportMaximumBytes: Int
    private let searchService = SearchService()
    private var regularSaveTasks: [UUID: Task<Void, Never>] = [:]
    private var regularSaveTokens: [UUID: UUID] = [:]
    private var vaultSaveTask: Task<Void, Never>?
    private var vaultSaveToken: UUID?
    private var vaultLockTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var hasStarted = false
    private var vaultOperationGeneration: UInt64 = 0
    private var isTerminationFlushInProgress = false
    private var inFlightPersistenceMutationCount = 0
    private var persistenceMutationDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isVaultLocking = false
    private(set) var isVaultImporting = false

    init(
        regularStore: (any RegularNoteStoring)? = nil,
        vaultStore: (any VaultStoring)? = nil,
        clipboard: ClipboardService? = nil,
        classifier: any ContentClassifying = ContentClassifier(),
        vaultImportMaximumBytes: Int = CappedFileReader.vaultImportMaximumBytes
    ) {
#if CLASP_VISUAL_QA
        // The visual-QA binary is a separate, compile-gated product. Its
        // synthetic stores make screenshot runs deterministic and prevent the
        // audit harness from reading or modifying a user's real notes or Vault.
        self.regularStore = regularStore ?? VisualQARegularNoteStore()
        self.vaultStore = vaultStore ?? VisualQAVaultStore()
        self.clipboard = clipboard ?? ClipboardService(client: VisualQAClipboardClient())
#else
        self.regularStore = regularStore ?? RegularNoteStore()
        self.vaultStore = vaultStore ?? VaultStore()
        self.clipboard = clipboard ?? ClipboardService()
#endif
        self.classifier = classifier
        self.vaultImportMaximumBytes = vaultImportMaximumBytes
    }

    var isVaultUnlocked: Bool { vaultNotes != nil }
    var allTags: [String] {
        Array(Set(regularNotes.filter { $0.trashedAt == nil }.flatMap(\.tags))).sorted()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        defer { isLoading = false }
        do {
            let persisted = try await regularStore.load()
            let earlyCaptures = Dictionary(uniqueKeysWithValues: regularNotes.map { ($0.id, $0) })
            regularNotes = persisted.map { earlyCaptures[$0.id] ?? $0 }
            let persistedIDs = Set(persisted.map(\.id))
            regularNotes.append(contentsOf: earlyCaptures.values.filter { !persistedIDs.contains($0.id) })
            regularNotes.sort { $0.updatedAt > $1.updatedAt }
        }
        catch { present(error) }
    }

    func notes(for destination: SidebarDestination) -> [Note] {
        noteResults(for: destination).map(\.note)
    }

    func noteResults(for destination: SidebarDestination) -> [SearchResult] {
        let results: [SearchResult]
        switch destination {
        case .allNotes, .trash:
            results = regularNotes.map { SearchResult(note: $0, source: .regular) }
                + (vaultNotes ?? []).map { SearchResult(note: $0, source: .vault) }
        case .vault:
            results = (vaultNotes ?? []).map { SearchResult(note: $0, source: .vault) }
        default:
            results = regularNotes.map { SearchResult(note: $0, source: .regular) }
        }

        return results.filter { result in
            let note = result.note
            return switch destination {
            case .inbox: note.isInInbox && note.trashedAt == nil && !note.isArchived
            case .allNotes: note.trashedAt == nil
            case .pinned: note.isPinned && note.trashedAt == nil
            case .vault: note.trashedAt == nil
            case .trash: note.trashedAt != nil
            case .tag(let tag): note.tags.contains(tag) && note.trashedAt == nil
            }
        }.sorted { lhs, rhs in
            if lhs.note.isPinned != rhs.note.isPinned { return lhs.note.isPinned }
            return lhs.note.updatedAt > rhs.note.updatedAt
        }
    }

    func search(_ query: String, in destination: SidebarDestination) -> [SearchResult] {
        let candidates = noteResults(for: destination)
        let regular = candidates.filter { $0.source == .regular }.map(\.note)
        let vault = candidates.filter { $0.source == .vault }.map(\.note)
        return searchService.search(query: query, regular: regular, vault: vault.isEmpty ? nil : vault)
    }

    @discardableResult
    func createRegular(body: String = "") -> UUID {
        guard !isTerminationFlushInProgress else { return UUID() }
        var note = Note(body: body)
        note.title = Note.deriveTitle(from: body)
        regularNotes.insert(note, at: 0)
        scheduleRegularSave(note, immediate: true)
        return note.id
    }

    @discardableResult
    func createVault(body: String = "") async -> UUID? {
        guard !isTerminationFlushInProgress, !isVaultImporting else { return nil }
        beginPersistenceMutation()
        defer { finishPersistenceMutation() }
        guard await ensureVaultUnlockedForAcceptedMutation() else { return nil }
        guard !isVaultImporting else { return nil }
        var note = Note(body: body)
        note.title = Note.deriveTitle(from: body)
        vaultNotes?.insert(note, at: 0)
        cancelPendingVaultSave()
        do {
            try await vaultStore.save(vaultNotes ?? [])
            return note.id
        } catch {
            if vaultNotes?.first(where: { $0.id == note.id }) == note {
                vaultNotes?.removeAll { $0.id == note.id }
            }
            present(error)
            return nil
        }
    }

    func updateRegular(_ note: Note, immediate: Bool = false) {
        guard !isTerminationFlushInProgress else { return }
        guard let index = regularNotes.firstIndex(where: { $0.id == note.id }) else { return }
        var changed = note
        changed.tags = Note.normalizedTags(changed.tags)
        changed.updatedAt = Date()
        regularNotes[index] = changed
        scheduleRegularSave(changed, immediate: immediate)
    }

    func updateVault(_ note: Note, immediate: Bool = false) {
        guard !isTerminationFlushInProgress, !isVaultImporting else { return }
        guard let index = vaultNotes?.firstIndex(where: { $0.id == note.id }) else { return }
        var changed = note
        changed.tags = Note.normalizedTags(changed.tags)
        changed.updatedAt = Date()
        vaultNotes?[index] = changed
        scheduleVaultSave(immediate: immediate)
    }

    /// Applies only fields owned by the editor. Organization and lifecycle
    /// flags may be changed concurrently from a list context menu, another
    /// window, or a global action and must never be overwritten by a stale
    /// editor snapshot.
    func updateEditorContent(
        id: UUID,
        isVault: Bool,
        title: String,
        body: String,
        tags: [String],
        immediate: Bool = false
    ) {
        guard !isTerminationFlushInProgress else { return }
        if isVault {
            guard !isVaultImporting,
                  let index = vaultNotes?.firstIndex(where: { $0.id == id }) else { return }
            vaultNotes?[index].title = title
            vaultNotes?[index].body = body
            vaultNotes?[index].tags = Note.normalizedTags(tags)
            vaultNotes?[index].updatedAt = Date()
            scheduleVaultSave(immediate: immediate)
        } else {
            guard let index = regularNotes.firstIndex(where: { $0.id == id }) else { return }
            regularNotes[index].title = title
            regularNotes[index].body = body
            regularNotes[index].tags = Note.normalizedTags(tags)
            regularNotes[index].updatedAt = Date()
            scheduleRegularSave(regularNotes[index], immediate: immediate)
        }
    }

    func trash(_ id: UUID, isVault: Bool) {
        mutate(id, isVault: isVault) { $0.trashedAt = Date() }
    }

    func restore(_ id: UUID, isVault: Bool) {
        mutate(id, isVault: isVault) { $0.trashedAt = nil }
    }

    func togglePin(_ id: UUID, isVault: Bool) {
        mutate(id, isVault: isVault) { $0.isPinned.toggle() }
    }

    func toggleArchive(_ id: UUID, isVault: Bool) {
        mutate(id, isVault: isVault) {
            $0.isArchived.toggle()
            if $0.isArchived { $0.isInInbox = false }
        }
    }

    func moveOutOfInbox(_ id: UUID) {
        mutate(id, isVault: false) { $0.isInInbox = false }
    }

    func permanentlyDelete(_ id: UUID, isVault: Bool) async {
        guard !isTerminationFlushInProgress else { return }
        do {
            if isVault {
                guard !isVaultImporting else { return }
                guard var notes = vaultNotes,
                      let removedIndex = notes.firstIndex(where: { $0.id == id }) else { return }
                beginPersistenceMutation()
                defer { finishPersistenceMutation() }
                let removed = notes.remove(at: removedIndex)
                cancelPendingVaultSave()
                vaultNotes = notes
                do {
                    try await vaultStore.save(notes)
                } catch {
                    if var current = vaultNotes, !current.contains(where: { $0.id == id }) {
                        current.insert(removed, at: min(removedIndex, current.endIndex))
                        vaultNotes = current
                    }
                    throw error
                }
            } else {
                guard let removedIndex = regularNotes.firstIndex(where: { $0.id == id }) else { return }
                beginPersistenceMutation()
                defer { finishPersistenceMutation() }
                let removed = regularNotes.remove(at: removedIndex)
                cancelPendingRegularSave(for: id)
                do {
                    try await regularStore.permanentlyDelete(id: id)
                } catch {
                    if !regularNotes.contains(where: { $0.id == id }) {
                        regularNotes.insert(removed, at: min(removedIndex, regularNotes.endIndex))
                    }
                    throw error
                }
            }
        } catch { present(error) }
    }

    func unlockVault() async -> Bool {
        guard !isTerminationFlushInProgress else { return false }
        beginPersistenceMutation()
        defer { finishPersistenceMutation() }
        return await unlockVaultForAcceptedMutation()
    }

    private func unlockVaultForAcceptedMutation() async -> Bool {
        guard !isVaultImporting else { return false }
        await waitForPendingVaultLock()
        let generation = vaultOperationGeneration
        do {
            let notes = try await vaultStore.unlock()
            guard generation == vaultOperationGeneration else {
                await vaultStore.lock()
                return false
            }
            vaultNotes = notes
            VaultLockCoordinator.shared.noteActivity()
            showStatus("Vault unlocked")
            return true
        } catch {
            guard generation == vaultOperationGeneration else { return false }
            present(error)
            return false
        }
    }

    func setupVault() async -> Bool {
        guard !isTerminationFlushInProgress, !isVaultImporting else { return false }
        beginPersistenceMutation()
        defer { finishPersistenceMutation() }
        await waitForPendingVaultLock()
        let generation = vaultOperationGeneration
        do {
            let notes = try await vaultStore.setup()
            guard generation == vaultOperationGeneration else {
                await vaultStore.lock()
                return false
            }
            vaultNotes = notes
            showStatus("Vault created")
            return true
        } catch {
            guard generation == vaultOperationGeneration else { return false }
            present(error)
            return false
        }
    }

    func lockVault() {
        guard !isTerminationFlushInProgress else { return }
        guard vaultLockTask == nil else { return }
        if isVaultImporting {
            vaultOperationGeneration &+= 1
            cancelPendingVaultSave()
            vaultNotes = nil
            isVaultLocking = true
            vaultLockTask = Task { [weak self] in
                guard let self else { return }
                await self.vaultStore.lock()
                self.isVaultLocking = false
                self.vaultLockTask = nil
            }
            showStatus("Vault locked")
            return
        }
        let snapshot = beginVaultLock()
        isVaultLocking = true
        vaultLockTask = Task { [weak self] in
            guard let self else { return }
            await self.persistVaultSnapshotAndLock(snapshot)
            self.isVaultLocking = false
            self.vaultLockTask = nil
        }
        showStatus("Vault locked")
    }

    func flushAndLockForTermination() async {
        isTerminationFlushInProgress = true
        await waitForPendingVaultLock()
        await waitForPersistenceMutationsToDrain()
        let regularSnapshot = regularNotes
        regularSaveTokens.removeAll()
        regularSaveTasks.values.forEach { $0.cancel() }
        regularSaveTasks.removeAll()
        let vaultSnapshot: [Note]?
        if isVaultImporting {
            // Invalidate the in-flight import without persisting its stale
            // pre-import model over the replacement container.
            vaultOperationGeneration &+= 1
            cancelPendingVaultSave()
            vaultNotes = nil
            vaultSnapshot = nil
        } else {
            vaultSnapshot = beginVaultLock()
        }
        isVaultLocking = true

        for note in regularSnapshot {
            do { try await regularStore.save(note) }
            catch { present(error) }
        }
        await persistVaultSnapshotAndLock(vaultSnapshot)
        isVaultLocking = false
    }

    func ensureVaultUnlocked() async -> Bool {
        guard !isTerminationFlushInProgress else { return false }
        beginPersistenceMutation()
        defer { finishPersistenceMutation() }
        return await ensureVaultUnlockedForAcceptedMutation()
    }

    private func ensureVaultUnlockedForAcceptedMutation() async -> Bool {
        if vaultNotes != nil { return true }
        return await unlockVaultForAcceptedMutation()
    }

    func saveClipboardToInbox() {
        guard let snapshot = clipboard.readContent() else {
            showStatus("Clipboard has no text or image")
            return
        }
        Task { _ = await capture(snapshot.content, to: .inbox) }
    }

    func capture(_ content: CapturedContent, to destination: CaptureDestination) async -> Bool {
        guard !isTerminationFlushInProgress else { return false }
        beginPersistenceMutation()
        defer { finishPersistenceMutation() }

        let classified = await classifier.classify(content)
        switch destination {
        case .inbox:
            let note = classified.note()
            regularNotes.insert(note, at: 0)
            do {
                try await regularStore.save(note)
            } catch {
                if regularNotes.first(where: { $0.id == note.id }) == note {
                    regularNotes.removeAll { $0.id == note.id }
                }
                present(error)
                return false
            }
            showStatus("Normal note added to Inbox")
            return true
        case .vault:
            guard !isVaultImporting else { return false }
            guard await ensureVaultUnlockedForAcceptedMutation() else { return false }
            guard !isVaultImporting else { return false }
            let note = classified.note()
            vaultNotes?.insert(note, at: 0)
            cancelPendingVaultSave()
            do {
                try await vaultStore.save(vaultNotes ?? [])
            } catch {
                if vaultNotes?.first(where: { $0.id == note.id }) == note {
                    vaultNotes?.removeAll { $0.id == note.id }
                }
                present(error)
                return false
            }
            showStatus("Private note added to Vault")
            return true
        }
    }

    func saveClipboardToVaultAndClear() async {
        guard let snapshot = clipboard.readContent() else {
            showStatus("Clipboard has no text or image")
            return
        }
        guard await capture(snapshot.content, to: .vault) else { return }
        let raw = UserDefaults.standard.string(forKey: PreferenceKeys.clipboardClearDelay)
            ?? ClipboardClearDelay.thirtySeconds.rawValue
        let delay = ClipboardClearDelay(rawValue: raw) ?? .thirtySeconds
        clipboard.scheduleSafeClear(of: snapshot, after: delay.duration)
        showStatus(
            delay == .never
                ? "Private note added to Vault"
                : "Private note added to Vault; clipboard clear scheduled"
        )
    }

    func clearClipboard() {
        clipboard.clearNow()
        showStatus("Clipboard cleared")
    }

    func saveQuickCapture(body: String, destination: CaptureDestination) async -> Bool {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return await capture(.text(body), to: destination)
    }

    func exportVault(to url: URL) async -> RecoveryKey? {
        guard !isTerminationFlushInProgress else { return nil }
        guard let vaultNotes else { return nil }
        do {
            let result = try await vaultStore.export(notes: vaultNotes)
            try result.data.write(to: url, options: .atomic)
            return result.recoveryKey
        } catch {
            present(error)
            return nil
        }
    }

    func importVault(from url: URL, recoveryKey: RecoveryKey) async -> Bool {
        guard !isTerminationFlushInProgress else { return false }
        beginPersistenceMutation()
        defer { finishPersistenceMutation() }
        await waitForPendingVaultLock()
        guard !isVaultImporting else { return false }
        isVaultImporting = true
        defer { isVaultImporting = false }
        let generation = vaultOperationGeneration
        let pendingSave = cancelPendingVaultSave()
        if let pendingSave { await pendingSave.value }
        guard generation == vaultOperationGeneration else { return false }
        do {
            let data = try CappedFileReader.read(url, maximumBytes: vaultImportMaximumBytes)
            guard generation == vaultOperationGeneration else { return false }
            let notes = try await vaultStore.importVault(data, recoveryKey: recoveryKey)
            guard generation == vaultOperationGeneration else {
                await vaultStore.lock()
                return false
            }
            vaultNotes = notes
            showStatus("Vault imported; previous container backed up")
            return true
        } catch {
            guard generation == vaultOperationGeneration else { return false }
            present(error)
            return false
        }
    }

    private func mutate(_ id: UUID, isVault: Bool, change: (inout Note) -> Void) {
        guard !isTerminationFlushInProgress else { return }
        if isVault {
            guard !isVaultImporting else { return }
            guard var notes = vaultNotes, let index = notes.firstIndex(where: { $0.id == id }) else { return }
            change(&notes[index])
            notes[index].updatedAt = Date()
            vaultNotes = notes
            scheduleVaultSave(immediate: true)
        } else {
            guard let index = regularNotes.firstIndex(where: { $0.id == id }) else { return }
            change(&regularNotes[index])
            regularNotes[index].updatedAt = Date()
            scheduleRegularSave(regularNotes[index], immediate: true)
        }
    }

    private func scheduleRegularSave(_ note: Note, immediate: Bool) {
        cancelPendingRegularSave(for: note.id)
        let token = UUID()
        regularSaveTokens[note.id] = token
        regularSaveTasks[note.id] = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(450)) }
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.regularStore.save(note)
            } catch {
                if self.regularSaveTokens[note.id] == token { self.present(error) }
            }
            guard self.regularSaveTokens[note.id] == token else { return }
            self.regularSaveTokens[note.id] = nil
            self.regularSaveTasks[note.id] = nil
        }
    }

    private func scheduleVaultSave(immediate: Bool) {
        cancelPendingVaultSave()
        let snapshot = vaultNotes ?? []
        let token = UUID()
        vaultSaveToken = token
        vaultSaveTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(450)) }
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.vaultStore.save(snapshot)
            } catch {
                if self.vaultSaveToken == token { self.present(error) }
            }
            guard self.vaultSaveToken == token else { return }
            self.vaultSaveToken = nil
            self.vaultSaveTask = nil
        }
    }

    private func cancelPendingRegularSave(for id: UUID) {
        regularSaveTokens[id] = nil
        let pendingSave = regularSaveTasks.removeValue(forKey: id)
        pendingSave?.cancel()
    }

    @discardableResult
    private func cancelPendingVaultSave() -> Task<Void, Never>? {
        vaultSaveToken = nil
        let pendingSave = vaultSaveTask
        vaultSaveTask = nil
        pendingSave?.cancel()
        return pendingSave
    }

    private func beginVaultLock() -> [Note]? {
        vaultOperationGeneration &+= 1
        cancelPendingVaultSave()
        let snapshot = vaultNotes
        vaultNotes = nil
        return snapshot
    }

    private func persistVaultSnapshotAndLock(_ snapshot: [Note]?) async {
        if let snapshot {
            do { try await vaultStore.save(snapshot) }
            catch { present(error) }
        }
        await vaultStore.lock()
    }

    private func waitForPendingVaultLock() async {
        if let vaultLockTask { await vaultLockTask.value }
    }

    private func beginPersistenceMutation() {
        inFlightPersistenceMutationCount += 1
    }

    private func finishPersistenceMutation() {
        precondition(inFlightPersistenceMutationCount > 0)
        inFlightPersistenceMutationCount -= 1
        guard inFlightPersistenceMutationCount == 0 else { return }
        let waiters = persistenceMutationDrainWaiters
        persistenceMutationDrainWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    private func waitForPersistenceMutationsToDrain() async {
        while inFlightPersistenceMutationCount > 0 {
            await withCheckedContinuation { continuation in
                persistenceMutationDrainWaiters.append(continuation)
            }
        }
    }

    private func showStatus(_ text: String) {
        statusTask?.cancel()
        statusMessage = text
        LocalConfirmationPresenter.shared.show(text)
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    private func present(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentedError = message
        LocalConfirmationPresenter.shared.show(message, kind: .error)
    }
}

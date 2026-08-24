import Foundation

struct SearchResult: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable { case regular, vault }
    var id: UUID { note.id }
    var note: Note
    var source: Source
}

struct SearchService: Sendable {
    func search(query: String, regular: [Note], vault: [Note]?) -> [SearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = regular.map { SearchResult(note: $0, source: .regular) }
            + (vault ?? []).map { SearchResult(note: $0, source: .vault) }
        guard !needle.isEmpty else { return candidates.sorted { $0.note.updatedAt > $1.note.updatedAt } }
        return candidates.filter { result in
            let searchable = ([result.note.title, result.note.body, result.note.extractedText, result.note.contentType.title] + result.note.tags)
                .joined(separator: "\n")
            return searchable.localizedCaseInsensitiveContains(needle)
        }.sorted { $0.note.updatedAt > $1.note.updatedAt }
    }
}

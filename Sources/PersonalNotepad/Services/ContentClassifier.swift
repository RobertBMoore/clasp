import Foundation
import Vision

struct ContentClassifier: Sendable {
    func classify(_ content: CapturedContent) async -> ClassifiedCapture {
        switch content {
        case .text(let text):
            return classifyText(text)
        case .styledText(let markdown, let plainText):
            return classifyText(plainText, storedBody: markdown)
        case .image(let image):
            let extracted = await Task.detached(priority: .userInitiated) {
                ImageTextExtractor.recognize(in: image.pngData)
            }.value
            let textClassification = classifyText(extracted)
            var tags = Set(textClassification.tags.filter { $0 != ClipContentType.note.rawValue })
            tags.insert(ClipContentType.image.rawValue)
            if let width = image.pixelWidth, let height = image.pixelHeight {
                tags.insert(width > height ? "landscape" : width < height ? "portrait" : "square")
            }
            let firstLine = extracted
                .split(whereSeparator: \Character.isNewline)
                .map(String.init)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let title = firstLine.map { "Image: \(String($0.prefix(90)))" } ?? "Image Clip"
            return ClassifiedCapture(
                title: title,
                body: "",
                tags: Note.normalizedTags(Array(tags)),
                contentType: .image,
                attachments: [NoteAttachment(data: image.pngData)],
                extractedText: extracted
            )
        }
    }

    private func classifyText(_ rawText: String, storedBody: String? = nil) -> ClassifiedCapture {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        var type: ClipContentType = .note
        var tags: Set<String> = []
        var title = Note.deriveTitle(from: text)

        if let url = exactWebURL(in: text) {
            type = .link
            tags.insert("link")
            if let host = url.host()?.lowercased().replacingOccurrences(of: "www.", with: "") {
                tags.insert(host)
                title = host
            }
        } else if looksLikeChecklist(text) {
            type = .checklist
            tags.formUnion(["checklist", "task"])
        } else if looksLikeCode(text) {
            type = .code
            tags.insert("code")
            if let language = detectedLanguage(in: text) { tags.insert(language) }
        } else if looksLikeContact(text) {
            type = .contact
            tags.insert("contact")
            if lower.range(of: #"[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"#, options: .regularExpression) != nil {
                tags.insert("email")
            }
            if lower.range(of: #"(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}"#, options: .regularExpression) != nil {
                tags.insert("phone")
            }
        }

        if hasMeetingSignals(lower) { tags.insert("meeting") }
        if lower.hasPrefix("idea:") || lower.hasPrefix("idea —") || lower.hasPrefix("idea -") { tags.insert("idea") }
        tags.insert(type.rawValue)

        return ClassifiedCapture(
            title: title,
            body: storedBody ?? text,
            tags: Note.normalizedTags(Array(tags)),
            contentType: type,
            attachments: [],
            extractedText: ""
        )
    }

    private func exactWebURL(in text: String) -> URL? {
        guard !text.contains(where: \Character.isNewline),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }

    private func looksLikeChecklist(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \Character.isNewline)
        return lines.filter {
            $0.range(of: #"^\s*(?:[-*]\s*\[[ xX]\]|☐|☑|✓|todo:)"#, options: [.regularExpression, .caseInsensitive]) != nil
        }.count >= min(2, max(1, lines.count))
    }

    private func looksLikeCode(_ text: String) -> Bool {
        guard text.count >= 24 else { return false }
        let patterns = [
            #"\b(func|class|struct|enum|protocol|import|let|var)\b"#,
            #"\b(function|const|async|await|return|interface)\b"#,
            #"\b(def|from|lambda|print|self)\b"#,
            #"[{};]\s*$"#,
            #"=>|==|!=|&&|\|\|"#
        ]
        let score = patterns.reduce(0) { result, pattern in
            result + (text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil ? 0 : 1)
        }
        return score >= 2
    }

    private func detectedLanguage(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("import swiftui") || lower.contains("func ") && lower.contains("let ") { return "swift" }
        if lower.contains("const ") || lower.contains("function ") || lower.contains("=>") { return "javascript" }
        if lower.contains("def ") && lower.contains(":") { return "python" }
        return nil
    }

    private func looksLikeContact(_ text: String) -> Bool {
        let email = text.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil
        let phone = text.range(of: #"(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}"#, options: .regularExpression) != nil
        return email || phone
    }

    private func hasMeetingSignals(_ text: String) -> Bool {
        let signals = ["agenda", "attendees", "meeting notes", "action items", "minutes:"]
        return signals.filter(text.contains).count >= 2
    }
}

private enum ImageTextExtractor {
    static func recognize(in data: Data) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(data: data, options: [:])
        do {
            try handler.perform([request])
            let recognized = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return String(recognized.prefix(100_000))
        } catch {
            return ""
        }
    }
}

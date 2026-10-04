import Foundation
import NaturalLanguage
import CoreServices

struct TranslationParagraph: Equatable, Identifiable {
    let id: Int
    let original: String
    let translation: String
}

struct WordDetails: Equatable {
    let word: String
    var definition: String?
    var isLookingUp = true
}

struct TranslationResult: Equatable {
    let original: String
    let source: Language?
    let target: Language
    let automatic: Bool
    let fromScreenshot: Bool
    var paragraphs: [TranslationParagraph] = []
    var word: WordDetails?
    var succeeded = false

    var direction: String { "\(source?.name ?? "Unknown language") → \(target.name)" }
    var translation: String { paragraphs.map(\.translation).joined(separator: "\n\n") }
}

// Pure text rules are shared by all translation entry points.
enum TranslationText {
    static func paragraphs(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let range = NSRange(normalized.startIndex..., in: normalized)
        let expression = try! NSRegularExpression(pattern: "\\n[\\t ]*\\n(?:[\\t ]*\\n)*")
        var start = normalized.startIndex
        var blocks: [String] = []
        for match in expression.matches(in: normalized, range: range) {
            guard let separator = Range(match.range, in: normalized) else { continue }
            blocks.append(String(normalized[start..<separator.lowerBound]))
            start = separator.upperBound
        }
        blocks.append(String(normalized[start...]))
        return blocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func englishWord(_ text: String) -> String? {
        let punctuation = CharacterSet(charactersIn: "\"“”‘’.,!?;:()[]{}«»")
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: punctuation)
        guard word.range(of: "^[A-Za-z]+(?:['’\\-][A-Za-z]+)*$", options: .regularExpression) != nil else { return nil }
        return word
    }

    static func detectLanguage(_ text: String) -> String? {
        if englishWord(text) != nil { return "en" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    static func definition(_ word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let value = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() else { return nil }
        let definition = (value as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return definition.isEmpty ? nil : definition
    }
}

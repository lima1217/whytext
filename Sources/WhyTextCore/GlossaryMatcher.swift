import Foundation

/// Finds the glossary terms a text uses, so translations keep the user's renderings.
public enum GlossaryMatcher {
    public static let defaultLimit = 20

    /// Entries for `targetLanguage` whose term appears in `text`, longest term first,
    /// at most `limit`. Words in spaced scripts match whole words only ("learning" is
    /// not in "learnings"); CJK and Hangul terms match anywhere, since those scripts
    /// don't separate words with spaces. Matching ignores case.
    public static func matches(
        in text: String,
        entries: [GlossaryEntry],
        targetLanguage: String,
        limit: Int = defaultLimit
    ) -> [GlossaryEntry] {
        let candidates = entries
            .filter { $0.targetLanguage == targetLanguage && !trimmed($0.term).isEmpty && !trimmed($0.rendering).isEmpty }
            .sorted { lhs, rhs in
                let (l, r) = (trimmed(lhs.term).count, trimmed(rhs.term).count)
                return l != r ? l > r : lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
            }
        var found: [GlossaryEntry] = []
        for entry in candidates where found.count < limit && contains(text, term: trimmed(entry.term)) {
            found.append(entry)
        }
        return found
    }

    /// Prepended to translate prompts; nil when no term matched.
    public static func hint(for entries: [GlossaryEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let lines = entries.map { "- \(trimmed($0.term)) → \(trimmed($0.rendering))" }
        return (["下列术语按给定译法翻译，不要改用别的说法："] + lines).joined(separator: "\n")
    }

    private static func contains(_ text: String, term: String) -> Bool {
        if term.unicodeScalars.contains(where: isUnspacedScript) {
            return text.range(of: term, options: .caseInsensitive) != nil
        }
        // Lookarounds instead of \b, so terms that start or end with symbols ("C++") still match.
        let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: term) + #"(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func isUnspacedScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, // Hiragana, Katakana
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F, // CJK ideographs
             0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: // Hangul
            return true
        default:
            return false
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

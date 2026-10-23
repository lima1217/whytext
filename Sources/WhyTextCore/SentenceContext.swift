import Foundation

/// The sentence around a selection, so a looked-up word keeps the line it was read in.
public enum SentenceContext {
    /// The sentence(s) covering `selectionUTF16` in `fullText`, on one line. Sentences
    /// longer than `maxLength` are cut around the selection, with "…" on cut ends.
    /// nil when the selection is already the whole sentence (nothing to add), when
    /// the range doesn't fit the text, or when the text at the range isn't
    /// `expectedSelection` (some apps report ranges that don't match their text).
    public static func extract(
        fullText: String,
        selectionUTF16: NSRange,
        expectedSelection: String? = nil,
        maxLength: Int = 400
    ) -> String? {
        let text = joiningWrappedLines(fullText)
        guard selectionUTF16.location != NSNotFound,
              selectionUTF16.length > 0,
              NSMaxRange(selectionUTF16) <= text.length else { return nil }

        var covering: NSRange?
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, stop in
            if range.location >= NSMaxRange(selectionUTF16) {
                stop.pointee = true
            } else if NSIntersectionRange(range, selectionUTF16).length > 0 {
                covering = covering.map { NSUnionRange($0, range) } ?? range
            }
        }
        guard var range = covering else { return nil }

        let selected = singleLine(text.substring(with: selectionUTF16))
        guard selected.count < maxLength else { return nil }
        if let expectedSelection, singleLine(expectedSelection) != selected { return nil }

        var cutStart = false
        var cutEnd = false
        if singleLine(text.substring(with: range)).count > maxLength {
            // Center a window of maxLength UTF-16 units on the selection, then widen
            // it to whole characters so emoji and combined marks stay intact.
            let center = selectionUTF16.location + selectionUTF16.length / 2
            var start = max(range.location, center - maxLength / 2)
            let end = min(NSMaxRange(range), start + maxLength)
            start = max(range.location, end - maxLength)
            let window = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
            cutStart = window.location > range.location
            cutEnd = NSMaxRange(window) < NSMaxRange(range)
            range = window
        }

        let sentence = singleLine(text.substring(with: range))
        guard sentence != selected else { return nil }
        return (cutStart ? "…" : "") + sentence + (cutEnd ? "…" : "")
    }

    /// Single line breaks become spaces, one for one so UTF-16 offsets still hold.
    /// PDFs and hard-wrapped text break lines mid-sentence, and the sentence
    /// splitter would otherwise end a sentence at every line. Blank lines stay
    /// paragraph breaks.
    private static func joiningWrappedLines(_ fullText: String) -> NSString {
        let text = NSMutableString(string: fullText)
        let newline = CharacterSet.newlines
        func isNewline(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
            return newline.contains(scalar)
        }
        for index in 0..<text.length where isNewline(index) && !isNewline(index - 1) && !isNewline(index + 1) {
            text.replaceCharacters(in: NSRange(location: index, length: 1), with: " ")
        }
        return text
    }

    /// Line breaks and runs of spaces become single spaces; ends are trimmed.
    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

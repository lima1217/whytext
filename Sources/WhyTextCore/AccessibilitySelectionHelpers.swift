import Foundation

/// Pure string helpers shared by accessibility selection code and unit tests.
public enum AccessibilitySelectionHelpers {
    public static func preview(_ text: String, maxLength: Int = 120) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: "\\n")
        if compact.count <= maxLength {
            return compact
        }
        let end = compact.index(compact.startIndex, offsetBy: maxLength)
        return String(compact[..<end]) + "..."
    }

    public static func nonEmptyTrimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func substringUTF16(_ text: String, location: Int, length: Int) -> String? {
        guard location >= 0, length > 0 else { return nil }

        let nsText = text as NSString
        let end = location + length
        guard end <= nsText.length else { return nil }

        return nsText.substring(with: NSRange(location: location, length: length))
    }

    public static func sanitizeSelectedText(_ raw: String) -> String {
        let normalizedLineEndings = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let withoutZeroWidth = normalizedLineEndings.replacingOccurrences(
            of: #"[\u200B\u200C\u200D\uFEFF\u2060]"#,
            with: "",
            options: .regularExpression
        )

        let compressedBlankLines = withoutZeroWidth.replacingOccurrences(
            of: #"\n[ \t]*\n(?:[ \t]*\n)+"#,
            with: "\n\n",
            options: .regularExpression
        )

        return compressedBlankLines.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

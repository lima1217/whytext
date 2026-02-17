import Foundation
import SwiftUI

struct MarkdownTextView: View {
    var markdown: String

    var body: some View {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text("")
        } else {
            let paragraphs = splitParagraphs(trimmed)
            if paragraphs.count <= 1 {
                Text(MarkdownRenderer.render(trimmed))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(MarkdownRenderer.render(paragraph))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Split on double-newlines (standard paragraph separator).
    /// Preserves single newlines within a paragraph.
    private func splitParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum MarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        var attributed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)

        attributed.font = .system(.body)

        for run in attributed.runs {
            let range = run.range
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributed[range].font = .system(.body, design: .monospaced)
            }
        }

        return attributed
    }

    static func plainText(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return String(attributed.characters)
        }
        return markdown
    }
}

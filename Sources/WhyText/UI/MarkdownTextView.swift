import AppKit
import Foundation
import SwiftUI
import WhyTextCore

struct MarkdownTextView: NSViewRepresentable {
    var markdown: String
    var fontSize: CGFloat = 16

    func makeNSView(context: Context) -> SelectableMarkdownTextView {
        let textView = SelectableMarkdownTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        return textView
    }

    func updateNSView(_ nsView: SelectableMarkdownTextView, context: Context) {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        nsView.setMarkdown(trimmed, fontSize: fontSize)
    }
}

final class SelectableMarkdownTextView: NSTextView {
    private var lastRenderedMarkdown: String = ""
    private var lastRenderedFontSize: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 0)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height + textContainerInset.height * 2)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(0, height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer?.containerSize = NSSize(width: max(0, newSize.width), height: .greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
    }

    func setMarkdown(_ markdown: String, fontSize: CGFloat) {
        guard markdown != lastRenderedMarkdown || fontSize != lastRenderedFontSize else { return }
        lastRenderedMarkdown = markdown
        lastRenderedFontSize = fontSize

        let rendered = markdown.isEmpty
            ? NSAttributedString(string: "")
            : MarkdownRenderer.renderNSAttributedString(markdown, fontSize: fontSize)

        textStorage?.setAttributedString(rendered)
        invalidateIntrinsicContentSize()
    }
}

enum MarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString {
        AttributedString(renderNSAttributedString(markdown))
    }

    static func renderNSAttributedString(_ markdown: String, fontSize: CGFloat = 16) -> NSAttributedString {
        let normalizedMarkdown = CJKLatinSpacer.apply(toPlainText: normalizeParagraphs(in: markdown))
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        let attributed = (try? AttributedString(markdown: normalizedMarkdown, options: options)) ?? AttributedString(normalizedMarkdown)

        let baseFont = NSFont.systemFont(ofSize: fontSize)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 10
        paragraphStyle.lineBreakMode = .byWordWrapping

        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        mutable.addAttribute(
            .font,
            value: baseFont,
            range: NSRange(location: 0, length: mutable.length)
        )

        mutable.addAttribute(
            NSAttributedString.Key.paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutable.length)
        )

        return mutable
    }

    static func plainText(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        let normalizedMarkdown = CJKLatinSpacer.apply(toPlainText: normalizeParagraphs(in: markdown))
        if let attributed = try? AttributedString(markdown: normalizedMarkdown, options: options) {
            return String(attributed.characters)
        }
        return normalizedMarkdown
    }

    private static func normalizeParagraphs(in text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var output: [String] = []
        var previousWasBlank = false

        for rawLine in normalizedNewlines.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let isBlank = line.isEmpty

            if isBlank {
                if !previousWasBlank, !output.isEmpty {
                    output.append("")
                }
                previousWasBlank = true
            } else {
                if shouldStartNewParagraph(after: output.last, current: line) {
                    output.append("")
                }
                output.append(line)
                previousWasBlank = false
            }
        }

        return output.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldStartNewParagraph(after previousLine: String?, current: String) -> Bool {
        guard let previousLine,
              !previousLine.isEmpty,
              !current.isEmpty,
              !previousLine.hasSuffix("  "),
              !previousLine.hasPrefix("#"),
              !previousLine.hasPrefix("- "),
              !previousLine.hasPrefix("* "),
              !current.hasPrefix("- "),
              !current.hasPrefix("* ") else {
            return false
        }

        let sentenceEndings = CharacterSet(charactersIn: ".!?。！？；;：:")
        guard let scalar = previousLine.unicodeScalars.last else { return false }
        return sentenceEndings.contains(scalar)
    }
}

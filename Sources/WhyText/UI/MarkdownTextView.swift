import AppKit
import Foundation
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    var markdown: String

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
        nsView.setMarkdown(trimmed)
    }
}

final class SelectableMarkdownTextView: NSTextView {
    private var lastRenderedMarkdown: String = ""

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

    func setMarkdown(_ markdown: String) {
        guard markdown != lastRenderedMarkdown else { return }
        lastRenderedMarkdown = markdown

        let rendered = markdown.isEmpty
            ? NSAttributedString(string: "")
            : MarkdownRenderer.renderNSAttributedString(markdown)

        textStorage?.setAttributedString(rendered)
        invalidateIntrinsicContentSize()
    }
}

enum MarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString {
        AttributedString(renderNSAttributedString(markdown))
    }

    static func renderNSAttributedString(_ markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        var attributed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)

        attributed.font = .system(.body)

        for run in attributed.runs {
            let range = run.range
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributed[range].font = .system(.body, design: .monospaced)
            }
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 10

        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        mutable.addAttribute(
            NSAttributedString.Key.paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutable.length)
        )

        return mutable
    }

    static func plainText(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return String(attributed.characters)
        }
        return markdown
    }
}

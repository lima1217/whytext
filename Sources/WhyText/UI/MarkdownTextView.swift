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
        let normalizedText = CJKLatinSpacer.apply(toPlainText: normalizeDisplayText(in: markdown))

        let baseFont = NSFont.systemFont(ofSize: fontSize)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Spacing.half      // 2
        paragraphStyle.paragraphSpacing = Spacing.x2_5 // 10
        paragraphStyle.lineBreakMode = .byWordWrapping

        let mutable = NSMutableAttributedString(string: normalizedText)
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
        CJKLatinSpacer.apply(toPlainText: normalizeDisplayText(in: markdown))
    }

    private static func normalizeDisplayText(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

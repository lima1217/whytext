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
    /// Body reading rhythm for translation / explanation copy (unitless ~1.5–1.6).
    private static let bodyLineHeightMultiple: CGFloat = 1.55
    /// Space after a paragraph. Blocks are joined with a single `\n`, so this
    /// alone owns inter-paragraph rhythm (do not also insert blank lines).
    private static func bodyParagraphSpacing(for fontSize: CGFloat) -> CGFloat {
        max(Spacing.x1_5, fontSize * 0.28)
    }

    static func render(_ markdown: String) -> AttributedString {
        AttributedString(renderNSAttributedString(markdown))
    }

    static func renderNSAttributedString(_ markdown: String, fontSize: CGFloat = 16) -> NSAttributedString {
        let normalizedText = CJKLatinSpacer.apply(toPlainText: normalizeDisplayText(in: markdown))
        guard !normalizedText.isEmpty else {
            return NSAttributedString(string: "")
        }

        guard let attributed = parseMarkdown(normalizedText) else {
            return styledPlainString(normalizedText, fontSize: fontSize)
        }
        return materialize(attributed, fontSize: fontSize)
    }

    static func plainText(_ markdown: String) -> String {
        let normalizedText = CJKLatinSpacer.apply(toPlainText: normalizePlainText(in: markdown))
        guard !normalizedText.isEmpty else { return "" }

        guard let attributed = parseMarkdown(normalizedText) else {
            return normalizedText
        }
        return materialize(attributed, fontSize: 16).string
    }

    /// Keep blank-line paragraph breaks; only squash runaway vertical gaps.
    private static func normalizeDisplayText(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: "\n{3,}",
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePlainText(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseMarkdown(_ text: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return try? AttributedString(markdown: text, options: options)
    }

    private static func styledPlainString(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: fullRange)
        mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        mutable.addAttribute(.paragraphStyle, value: bodyParagraphStyle(fontSize: fontSize), range: fullRange)
        return mutable
    }

    /// Foundation markdown yields presentation intents without fonts or newlines.
    /// Materialize them into an NSTextView-friendly attributed string.
    private static func materialize(_ attributed: AttributedString, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = bodyParagraphStyle(fontSize: fontSize)
        var previousBlockID: Int?
        var previousListItemID: Int?
        var didEmitListPrefixForItem = false

        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            guard !text.isEmpty else { continue }

            let block = blockContext(from: run.presentationIntent)
            if let previousBlockID, previousBlockID != block.id {
                let separator = blockSeparator(from: previousBlockID, to: block)
                if !separator.isEmpty {
                    result.append(NSAttributedString(
                        string: separator,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: fontSize),
                            .foregroundColor: NSColor.labelColor,
                            .paragraphStyle: paragraphStyle,
                        ]
                    ))
                }
                previousListItemID = nil
                didEmitListPrefixForItem = false
            }

            if let listItemID = block.listItemID {
                if previousListItemID != listItemID {
                    previousListItemID = listItemID
                    didEmitListPrefixForItem = false
                }
                if !didEmitListPrefixForItem {
                    let prefix = listPrefix(for: block)
                    result.append(NSAttributedString(
                        string: prefix,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: fontSize),
                            .foregroundColor: NSColor.labelColor,
                            .paragraphStyle: paragraphStyle,
                        ]
                    ))
                    didEmitListPrefixForItem = true
                }
            }

            let font = font(
                bodySize: fontSize,
                inlineIntent: run.inlinePresentationIntent,
                headerLevel: block.headerLevel,
                isCodeBlock: block.isCodeBlock
            )
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: block.isCodeBlock || isCode(run.inlinePresentationIntent)
                    ? NSColor.secondaryLabelColor
                    : NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
            }
            if isStrikethrough(run.inlinePresentationIntent) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }

            result.append(NSAttributedString(string: text, attributes: attributes))
            previousBlockID = block.id
        }

        return result
    }

    private static func bodyParagraphStyle(fontSize: CGFloat) -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = bodyLineHeightMultiple
        paragraphStyle.paragraphSpacing = bodyParagraphSpacing(for: fontSize)
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .natural
        paragraphStyle.hyphenationFactor = 0.35
        return paragraphStyle
    }

    private struct BlockContext {
        var id: Int
        var headerLevel: Int?
        var listItemID: Int?
        var listOrdinal: Int?
        var isOrderedList: Bool
        var isCodeBlock: Bool
    }

    private static func blockContext(from intent: PresentationIntent?) -> BlockContext {
        guard let intent else {
            return BlockContext(
                id: 0,
                headerLevel: nil,
                listItemID: nil,
                listOrdinal: nil,
                isOrderedList: false,
                isCodeBlock: false
            )
        }

        var headerLevel: Int?
        var listItemID: Int?
        var listOrdinal: Int?
        var isOrderedList = false
        var isCodeBlock = false
        var blockID = intent.components.last?.identity ?? 0

        for component in intent.components {
            switch component.kind {
            case .header(let level):
                headerLevel = level
                blockID = component.identity
            case .listItem(let ordinal):
                listItemID = component.identity
                listOrdinal = ordinal
                blockID = component.identity
            case .orderedList:
                isOrderedList = true
            case .unorderedList:
                isOrderedList = false
            case .codeBlock:
                isCodeBlock = true
                blockID = component.identity
            case .paragraph, .blockQuote, .thematicBreak:
                blockID = component.identity
            default:
                continue
            }
        }

        return BlockContext(
            id: blockID,
            headerLevel: headerLevel,
            listItemID: listItemID,
            listOrdinal: listOrdinal,
            isOrderedList: isOrderedList,
            isCodeBlock: isCodeBlock
        )
    }

    private static func blockSeparator(from _: Int, to _: BlockContext) -> String {
        // Single newline between blocks; `paragraphSpacing` provides the gap.
        // A blank `\n\n` line would become its own paragraph and double the space.
        "\n"
    }

    private static func listPrefix(for block: BlockContext) -> String {
        if block.isOrderedList, let ordinal = block.listOrdinal {
            return "\(ordinal). "
        }
        return "• "
    }

    private static func font(
        bodySize: CGFloat,
        inlineIntent: InlinePresentationIntent?,
        headerLevel: Int?,
        isCodeBlock: Bool
    ) -> NSFont {
        if isCodeBlock || isCode(inlineIntent) {
            let size = bodySize * 0.94
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }

        let size: CGFloat
        var weight: NSFont.Weight = .regular
        if let headerLevel {
            switch headerLevel {
            case 1:
                size = bodySize * 1.35
                weight = .bold
            case 2:
                size = bodySize * 1.22
                weight = .bold
            case 3:
                size = bodySize * 1.12
                weight = .semibold
            default:
                size = bodySize * 1.06
                weight = .semibold
            }
        } else {
            size = bodySize
        }

        if isStrong(inlineIntent) {
            weight = weight == .regular ? .semibold : .bold
        }

        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if isEmphasis(inlineIntent) {
            let italic = base.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: italic, size: size) ?? base
        }
        return base
    }

    private static func isStrong(_ intent: InlinePresentationIntent?) -> Bool {
        guard let intent else { return false }
        return intent.contains(.stronglyEmphasized)
    }

    private static func isEmphasis(_ intent: InlinePresentationIntent?) -> Bool {
        guard let intent else { return false }
        return intent.contains(.emphasized)
    }

    private static func isCode(_ intent: InlinePresentationIntent?) -> Bool {
        guard let intent else { return false }
        return intent.contains(.code)
    }

    private static func isStrikethrough(_ intent: InlinePresentationIntent?) -> Bool {
        guard let intent else { return false }
        return intent.contains(.strikethrough)
    }
}

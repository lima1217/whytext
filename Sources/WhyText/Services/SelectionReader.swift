import Foundation
import WhyTextCore

final class SelectionReader {
    private let accessibility: AccessibilitySelectionService
    private let clipboardFallback: ClipboardSelectionFallbackService

    init(
        accessibility: AccessibilitySelectionService = AccessibilitySelectionService(),
        clipboardFallback: ClipboardSelectionFallbackService = ClipboardSelectionFallbackService()
    ) {
        self.accessibility = accessibility
        self.clipboardFallback = clipboardFallback
    }

    struct Result: Equatable {
        var text: String
        var anchorRect: CGRect?
        /// Where the selection was read; nil when nothing was read.
        var source: LookupSource?
    }

    @MainActor
    func readSelectedText(allowClipboardFallback: Bool = true) async throws -> Result {
        if accessibility.status() == .trusted {
            if let selection = try? accessibility.getSelectedTextResult(), !selection.text.isEmpty {
                var source = accessibility.captureSource()
                source.sentence = selection.sentence
                return Result(text: selection.text, anchorRect: selection.anchorRect, source: source)
            }

            if allowClipboardFallback,
               let fallbackText = await clipboardFallback.readSelectedTextViaCopy(), !fallbackText.isEmpty {
                return Result(text: fallbackText, anchorRect: nil, source: accessibility.captureSource())
            }

            throw SelectionError.noSelection
        }

        throw SelectionError.notTrusted
    }
}

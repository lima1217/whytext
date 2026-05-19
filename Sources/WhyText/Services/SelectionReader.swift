import Foundation

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
    }

    func readSelectedText(allowClipboardFallback: Bool = true) async throws -> Result {
        if accessibility.status() == .trusted {
            if let selection = try? accessibility.getSelectedTextResult(), !selection.text.isEmpty {
                return Result(text: selection.text, anchorRect: selection.anchorRect)
            }

            if allowClipboardFallback,
               let fallbackText = await clipboardFallback.readSelectedTextViaCopy(), !fallbackText.isEmpty {
                return Result(text: fallbackText, anchorRect: nil)
            }

            throw SelectionError.noSelection
        }

        throw SelectionError.notTrusted
    }
}

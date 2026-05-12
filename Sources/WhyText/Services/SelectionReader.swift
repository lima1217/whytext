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
    }

    func readSelectedText(allowClipboardFallback: Bool = true) async throws -> Result {
        if accessibility.status() == .trusted {
            if let text = try? accessibility.getSelectedText(), !text.isEmpty {
                return Result(text: text)
            }

            if allowClipboardFallback,
               let fallbackText = await clipboardFallback.readSelectedTextViaCopy(), !fallbackText.isEmpty {
                return Result(text: fallbackText)
            }

            throw SelectionError.noSelection
        }

        throw SelectionError.notTrusted
    }
}

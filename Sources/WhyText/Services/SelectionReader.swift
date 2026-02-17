import Foundation

final class SelectionReader {
    private let accessibility: AccessibilitySelectionService

    init(
        accessibility: AccessibilitySelectionService = AccessibilitySelectionService()
    ) {
        self.accessibility = accessibility
    }

    struct Result: Equatable {
        var text: String
    }

    func readSelectedText() async throws -> Result {
        if accessibility.status() == .trusted {
            if let text = try? accessibility.getSelectedText(), !text.isEmpty {
                return Result(text: text)
            }
            throw SelectionError.noSelection
        }

        throw SelectionError.notTrusted
    }
}

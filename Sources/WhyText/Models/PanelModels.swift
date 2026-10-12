import Foundation
import WhyTextCore

struct PanelState: Equatable {
    var selectedText: String = ""
    var isLoading: Bool = false
    var resultText: String = ""
    var errorMessage: String?
    var noticeMessage: String?
    /// Thinking / searching before visible text arrives; cleared once text streams.
    var activity: LLMActivity?
    var lastAction: PanelAction?
    var lastInputText: String?
    var phase: PanelPhase = .choose
}

enum PanelPhase: String, Codable, Equatable {
    case choose
    case result
}

enum PanelAction: String, Codable, CaseIterable {
    case translate
    case explain

    var displayName: String {
        switch self {
        case .translate:
            "翻译"
        case .explain:
            "解释"
        }
    }

    var translationMode: TranslationMode {
        switch self {
        case .translate:
            .translate
        case .explain:
            .explain
        }
    }
}

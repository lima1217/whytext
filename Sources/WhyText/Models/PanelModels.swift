import Foundation
import WhyTextCore

struct PanelState: Equatable {
    var selectedText: String = ""
    var isLoading: Bool = false
    var resultText: String = ""
    var errorMessage: String? {
        // Each new error starts as not-a-settings-problem; callers opt in after.
        didSet { errorNeedsSettings = false }
    }
    /// The error is fixed in Settings (provider, API key, base URL, permissions).
    var errorNeedsSettings: Bool = false
    var noticeMessage: String?
    /// Thinking / searching before visible text arrives; cleared once text streams.
    var activity: LLMActivity?
    var lastAction: PanelAction?
    var lastInputText: String?
    var phase: PanelPhase = .choose
    /// Language the current translation targets; nil for explanations.
    var targetLanguage: TranslationLanguage?
    /// Prompt and answers replayed as context for the next follow-up question.
    /// Empty until the first answer completes.
    var conversation: [ConversationMessage] = []
    var followUps: [FollowUpTurn] = []
    /// The result was restored from history instead of requested.
    var isFromHistory: Bool = false

    var canAskFollowUp: Bool {
        !isLoading && !conversation.isEmpty && (errorMessage?.isEmpty ?? true)
    }
}

struct FollowUpTurn: Equatable, Identifiable {
    let id = UUID()
    var question: String
    var answer: String = ""
    var errorMessage: String?
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

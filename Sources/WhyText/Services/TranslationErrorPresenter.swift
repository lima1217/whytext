import Foundation
import WhyTextCore

enum TranslationErrorPresenter {
    /// Errors the user resolves by editing the provider in Settings.
    static func needsSettings(for error: Error) -> Bool {
        if case SelectionError.notTrusted = error { return true }
        guard let llmError = error as? LLMError else { return false }
        switch llmError.errorCode {
        case .unauthorized, .noPermission, .invalidBaseURL:
            return true
        case .rateLimited, .timeout, .network, .emptyResponse, .invalidResponse, .unknown:
            return false
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        if let llmError = error as? LLMError {
            return llmError.localizedDescription
        }

        let message = error.localizedDescription
        let lowercased = message.lowercased()

        if lowercased.contains("401") || lowercased.contains("unauthorized") || lowercased.contains("invalid key") {
            return L10n.t("API Key 无效或已过期。请在设置中更新后重试。")
        }
        if lowercased.contains("429") || lowercased.contains("rate limit") {
            return L10n.t("请求过于频繁，请稍后重试。")
        }
        if lowercased.contains("timed out") || lowercased.contains("timeout") {
            return L10n.t("网络超时。请检查网络后重试。")
        }
        if lowercased.contains("403") || lowercased.contains("forbidden") || lowercased.contains("permission") {
            return L10n.t("无权限访问该模型或接口。请检查 API Key 与模型名称。")
        }
        if lowercased.contains("empty") || lowercased.contains("no content") {
            return L10n.t("模型未返回内容。请重试，或换一个模型。")
        }

        return message
    }
}

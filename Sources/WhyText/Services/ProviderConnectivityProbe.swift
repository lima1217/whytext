import Foundation
import WhyTextCore

struct ProviderConnectivityProbe {
    private let llmClient: LLMClient

    init(llmClient: LLMClient) {
        self.llmClient = llmClient
    }

    func test(provider: LLMProvider, apiKey: String) async -> ProviderConnectivityReport {
        var report = ProviderConnectivityReport(
            baseURL: .unknown,
            apiKey: .unknown,
            model: .unknown,
            message: ""
        )

        let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedBaseURL.isEmpty || URL(string: trimmedBaseURL) == nil {
            report.baseURL = .unavailable
            report.message = L10n.t("请填写有效的 Base URL，例如 https://api.deepseek.com")
        } else {
            report.baseURL = .available
        }

        if trimmedAPIKey.isEmpty {
            report.apiKey = .unavailable
            report.message = report.message.isEmpty ? L10n.t("请填写 API Key") : report.message
        } else {
            report.apiKey = .available
        }

        if trimmedModel.isEmpty {
            report.model = .unavailable
            report.message = report.message.isEmpty ? L10n.t("请填写 Model 名称") : report.message
        } else {
            report.model = .available
        }

        guard report.baseURL != .unavailable,
              report.apiKey != .unavailable,
              report.model != .unavailable else {
            return report
        }

        var probeProvider = provider
        probeProvider.baseURL = trimmedBaseURL
        probeProvider.model = trimmedModel

        do {
            _ = try await llmClient.complete(
                prompt: "Reply with exactly: OK",
                provider: probeProvider,
                apiKey: trimmedAPIKey
            )

            report.baseURL = .available
            report.apiKey = .available
            report.model = .available
            report.message = L10n.t("连通成功")
            return report
        } catch let error as LLMError {
            let message = connectivityErrorMessage(for: error)
            report.message = message
            applyConnectivityErrorCode(error.errorCode, to: &report)
            inferConnectivityFailures(from: message, report: &report)
            return report
        } catch {
            let message = TranslationErrorPresenter.userFacingMessage(for: error)
            report.message = message
            inferConnectivityFailures(from: message, report: &report)
            return report
        }
    }

    private func applyConnectivityErrorCode(_ code: TranslationErrorCode, to report: inout ProviderConnectivityReport) {
        switch code {
        case .unauthorized:
            report.apiKey = .unavailable
        case .rateLimited:
            report.model = report.model == .unknown ? .available : report.model
        case .timeout, .network:
            report.baseURL = .unavailable
        case .noPermission:
            report.apiKey = .unavailable
            report.model = .unavailable
        case .emptyResponse:
            report.model = .unavailable
        case .invalidResponse:
            report.model = .unavailable
        case .invalidBaseURL:
            report.baseURL = .unavailable
        case .unknown:
            break
        }
    }

    private func connectivityErrorMessage(for error: LLMError) -> String {
        if let reason = error.failureReason,
           !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(error.localizedDescription)\n\(reason)"
        }

        return error.localizedDescription
    }

    private func inferConnectivityFailures(from message: String, report: inout ProviderConnectivityReport) {
        let lowercased = message.lowercased()

        if lowercased.contains("api key")
            || lowercased.contains("unauthorized")
            || lowercased.contains("invalid key")
            || lowercased.contains("401")
            || lowercased.contains("403") {
            report.apiKey = .unavailable
        }

        if lowercased.contains("model")
            || lowercased.contains("not found")
            || lowercased.contains("does not exist") {
            report.model = .unavailable
        }

        if lowercased.contains("base url")
            || lowercased.contains("invalid url")
            || lowercased.contains("host")
            || lowercased.contains("dns")
            || lowercased.contains("timed out")
            || lowercased.contains("cannot connect") {
            report.baseURL = .unavailable
        }
    }
}

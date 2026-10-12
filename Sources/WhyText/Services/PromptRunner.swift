import Foundation
import WhyTextCore

final class PromptRunner {
    private let llmClient: LLMClient

    init(llmClient: LLMClient) {
        self.llmClient = llmClient
    }

    func run(
        template: String,
        chunks: [String],
        provider: LLMProvider,
        apiKey: String,
        enableStreaming: Bool,
        mode: TranslationMode = .translate,
        targetLanguage: String = "auto",
        history: [ConversationMessage] = [],
        onActivity: @escaping (LLMActivity) async -> Void = { _ in },
        onUpdate: @escaping (String) async -> Void
    ) async throws -> String {
        var output = ""
        var lastActivity: LLMActivity?
        var lastUpdate = Date.distantPast

        func maybeUpdate(_ text: String, force: Bool = false) async {
            let now = Date()
            // Each update re-parses and re-lays-out the whole Markdown result, so
            // keep the cadence modest; long outputs otherwise grow quadratically.
            if force || now.timeIntervalSince(lastUpdate) >= 0.12 {
                lastUpdate = now
                await onUpdate(text)
            }
        }

        for (idx, chunk) in chunks.enumerated() {
            try Task.checkCancellation()

            let request = buildRequest(
                template: template,
                text: chunk,
                model: provider.model,
                stream: enableStreaming,
                mode: mode,
                targetLanguage: targetLanguage,
                history: history
            )

            if idx > 0 {
                output += "\n\n"
                await maybeUpdate(output, force: true)
            }

            if enableStreaming {
                var current = ""
                do {
                    for try await event in llmClient.stream(
                        request: request,
                        provider: provider,
                        apiKey: apiKey
                    ) {
                        try Task.checkCancellation()
                        switch event {
                        case .text(let delta):
                            current.append(delta)
                            lastActivity = nil
                            await maybeUpdate(output + current)
                        case .activity(let activity):
                            guard activity != lastActivity else { continue }
                            lastActivity = activity
                            await onActivity(activity)
                        }
                    }
                    output += current
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LLMError where error.shouldAttemptNonStreamingFallback {
                    var fallbackRequest = request
                    fallbackRequest.stream = false

                    let response = try await llmClient.complete(
                        request: fallbackRequest,
                        provider: provider,
                        apiKey: apiKey
                    )
                    output += response.translatedText
                    await maybeUpdate(output, force: true)
                } catch {
                    throw error
                }
            } else {
                let response = try await llmClient.complete(
                    request: request,
                    provider: provider,
                    apiKey: apiKey
                )
                output += response.translatedText
                await maybeUpdate(output, force: true)
            }
        }

        await maybeUpdate(output, force: true)

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw LLMError.emptyOutput
        }
        return trimmed
    }

    /// The user turn a follow-up conversation replays: the whole input in one prompt,
    /// even when the original run was split into chunks.
    func transcriptPrompt(
        template: String,
        text: String,
        mode: TranslationMode,
        targetLanguage: String
    ) -> String {
        buildRequest(
            template: template,
            text: text,
            model: "",
            stream: false,
            mode: mode,
            targetLanguage: targetLanguage,
            history: []
        )
        .renderedPrompt(supportsWebSearch: false)
    }

    private func buildRequest(
        template: String,
        text: String,
        model: String,
        stream: Bool,
        mode: TranslationMode,
        targetLanguage: String,
        history: [ConversationMessage]
    ) -> UnifiedTranslationRequest {
        UnifiedTranslationRequest(
            model: model,
            sourceText: text,
            sourceLanguage: "auto",
            targetLanguage: targetLanguage,
            mode: mode,
            promptTemplate: template,
            stream: stream,
            // The paragraph hint is for translating source text, not answering questions.
            includeStructureHint: mode == .translate && history.isEmpty,
            enableWebSearch: mode == .explain,
            history: history
        )
    }
}

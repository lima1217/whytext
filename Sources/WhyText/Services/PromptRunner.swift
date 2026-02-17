import Foundation

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
        onUpdate: @escaping (String) async -> Void
    ) async throws -> String {
        var output = ""
        var lastUpdate = Date.distantPast

        func maybeUpdate(_ text: String, force: Bool = false) async {
            let now = Date()
            if force || now.timeIntervalSince(lastUpdate) >= 0.05 {
                lastUpdate = now
                await onUpdate(text)
            }
        }

        for (idx, chunk) in chunks.enumerated() {
            try Task.checkCancellation()

            let translationRequest = buildTranslationRequest(
                template: template,
                text: chunk,
                model: provider.model,
                stream: enableStreaming
            )

            if idx > 0 {
                output += "\n\n"
                await maybeUpdate(output, force: true)
            }

            if enableStreaming {
                var current = ""
                do {
                    for try await delta in llmClient.stream(
                        request: translationRequest,
                        provider: provider,
                        apiKey: apiKey
                    ) {
                        try Task.checkCancellation()
                        current.append(delta)
                        await maybeUpdate(output + current)
                    }
                    output += current
                } catch {
                    var fallbackRequest = translationRequest
                    fallbackRequest.stream = false

                    let response = try await llmClient.complete(
                        request: fallbackRequest,
                        provider: provider,
                        apiKey: apiKey
                    )
                    output += response.translatedText
                    await maybeUpdate(output, force: true)
                }
            } else {
                let response = try await llmClient.complete(
                    request: translationRequest,
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

    private func buildTranslationRequest(
        template: String,
        text: String,
        model: String,
        stream: Bool
    ) -> UnifiedTranslationRequest {
        UnifiedTranslationRequest(
            model: model,
            sourceText: text,
            sourceLanguage: "auto",
            targetLanguage: "zh-Hans",
            mode: .translate,
            device: UnifiedTranslationRequest.defaultDeviceDescriptor,
            promptTemplate: template,
            stream: stream
        )
    }
}

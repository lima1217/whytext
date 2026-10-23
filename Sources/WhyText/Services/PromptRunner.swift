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
        /// One per chunk; nil (or missing) where a chunk uses no glossary term.
        glossaryHints: [String?] = [],
        onActivity: @escaping (LLMActivity) async -> Void = { _ in },
        onUpdate: @escaping (String) async -> Void
    ) async throws -> String {
        let progress = ChunkProgress(
            count: chunks.count,
            onActivity: onActivity,
            onUpdate: onUpdate
        )

        // Chunks run concurrently (bounded, to stay clear of rate limits) and are shown
        // in order. A failed chunk cancels the rest: a translation with a hole is worse
        // than a retry.
        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextIndex = 0

            func startNext() {
                guard nextIndex < chunks.count else { return }
                let index = nextIndex
                let request = buildRequest(
                    template: template,
                    text: chunks[index],
                    model: provider.model,
                    stream: enableStreaming,
                    mode: mode,
                    targetLanguage: targetLanguage,
                    history: history,
                    glossaryHint: index < glossaryHints.count ? glossaryHints[index] : nil
                )
                nextIndex += 1
                group.addTask {
                    let text = try await self.runChunk(
                        request: request,
                        provider: provider,
                        apiKey: apiKey,
                        onActivity: { activity in await progress.activity(activity) },
                        onPartial: { partial in await progress.partial(partial, at: index) }
                    )
                    await progress.finish(text, at: index)
                }
            }

            for _ in 0..<min(Self.maxConcurrentChunks, chunks.count) {
                startNext()
            }
            while try await group.next() != nil {
                startNext()
            }
        }

        let output = await progress.flush()

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw LLMError.emptyOutput
        }
        return trimmed
    }

    private static let maxConcurrentChunks = 3

    /// One request, streamed when enabled, with a single non-streaming fallback for
    /// providers whose streaming endpoint misbehaves. Returns the chunk's full text.
    private func runChunk(
        request: UnifiedTranslationRequest,
        provider: LLMProvider,
        apiKey: String,
        onActivity: @escaping (LLMActivity) async -> Void,
        onPartial: @escaping (String) async -> Void
    ) async throws -> String {
        try Task.checkCancellation()

        guard request.stream else {
            let response = try await llmClient.complete(request: request, provider: provider, apiKey: apiKey)
            return response.translatedText
        }

        var current = ""
        do {
            for try await event in llmClient.stream(request: request, provider: provider, apiKey: apiKey) {
                try Task.checkCancellation()
                switch event {
                case .text(let delta):
                    current.append(delta)
                    await onPartial(current)
                case .activity(let activity):
                    await onActivity(activity)
                }
            }
            // A cancelled consumer ends the stream early instead of throwing.
            try Task.checkCancellation()
            return current
        } catch let error as LLMError where error.shouldAttemptNonStreamingFallback {
            var fallbackRequest = request
            fallbackRequest.stream = false
            let response = try await llmClient.complete(request: fallbackRequest, provider: provider, apiKey: apiKey)
            return response.translatedText
        }
    }

    /// The user turn a follow-up conversation replays: the whole input in one prompt,
    /// even when the original run was split into chunks.
    func transcriptPrompt(
        template: String,
        text: String,
        mode: TranslationMode,
        targetLanguage: String,
        glossaryHint: String?
    ) -> String {
        buildRequest(
            template: template,
            text: text,
            model: "",
            stream: false,
            mode: mode,
            targetLanguage: targetLanguage,
            history: [],
            glossaryHint: glossaryHint
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
        history: [ConversationMessage],
        glossaryHint: String? = nil
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
            history: history,
            glossaryHint: glossaryHint
        )
    }
}

/// Collects chunk output from concurrent tasks and forwards throttled, in-order
/// updates to the UI.
private actor ChunkProgress {
    private var assembly: ChunkAssembly
    private var lastActivity: LLMActivity?
    private var lastUpdate = Date.distantPast
    private var lastSent: String?
    private let onActivity: (LLMActivity) async -> Void
    private let onUpdate: (String) async -> Void

    init(
        count: Int,
        onActivity: @escaping (LLMActivity) async -> Void,
        onUpdate: @escaping (String) async -> Void
    ) {
        self.assembly = ChunkAssembly(count: count)
        self.onActivity = onActivity
        self.onUpdate = onUpdate
    }

    func activity(_ activity: LLMActivity) async {
        guard activity != lastActivity else { return }
        lastActivity = activity
        await onActivity(activity)
    }

    func partial(_ text: String, at index: Int) async {
        lastActivity = nil
        assembly.setPartial(text, at: index)
        await send(force: false)
    }

    func finish(_ text: String, at index: Int) async {
        assembly.finish(text, at: index)
        await send(force: true)
    }

    /// Sends the final text if throttling held it back; returns the full output.
    func flush() async -> String {
        await send(force: true)
        return assembly.fullText
    }

    private func send(force: Bool) async {
        let text = assembly.visibleText
        guard text != lastSent else { return }
        let now = Date()
        // Each update re-parses and re-lays-out the whole Markdown result, so
        // keep the cadence modest; long outputs otherwise grow quadratically.
        guard force || now.timeIntervalSince(lastUpdate) >= 0.12 else { return }
        lastUpdate = now
        lastSent = text
        await onUpdate(text)
    }
}

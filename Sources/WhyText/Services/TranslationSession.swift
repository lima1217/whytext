import Foundation
import WhyTextCore

@MainActor
final class TranslationSession {
    private let promptRunner: PromptRunner
    private var runningTask: Task<Void, Never>?
    private var runGeneration = 0

    init(promptRunner: PromptRunner) {
        self.promptRunner = promptRunner
    }

    func cancel() {
        // Keep the current generation so the cancelled task can still deliver
        // onFinished(.success) and clear UI loading state. A newer run() bumps
        // generation and ignores that stale completion.
        runningTask?.cancel()
    }

    /// Runs a translate/explain prompt over the selection. On success, `onFinished`
    /// receives the transcript (prompt + answer) that follow-up questions replay;
    /// a cancelled run finishes with an empty transcript.
    func run(
        mode: TranslationMode,
        template: String,
        selectedText: String,
        targetLanguage: TranslationLanguage,
        provider: LLMProvider,
        apiKey: String,
        maxInputCharacters: Int,
        splitLongInput: Bool,
        enableStreaming: Bool,
        glossary: [GlossaryEntry],
        contextHint: String?,
        onNotice: @escaping (String?) -> Void,
        onActivity: @escaping (LLMActivity) -> Void,
        onPartialResult: @escaping (String) -> Void,
        onFinished: @escaping (Result<[ConversationMessage], Error>) -> Void
    ) {
        launch(onFinished: onFinished, cancelledValue: []) { [promptRunner] deliver in
            // Explanations summarize the whole passage; per-chunk runs would
            // repeat the "one-line gist" step once per chunk, so truncate instead.
            let chunking = TextChunker.chunk(
                text: selectedText,
                maxCharacters: maxInputCharacters,
                splitLongInput: splitLongInput && mode == .translate
            )

            if chunking.wasTruncated {
                await deliver { onNotice(L10n.f("输入过长，已截断到 %@ 字符", String(maxInputCharacters))) }
            } else if selectedText.count > maxInputCharacters && chunking.chunks.count > 1 {
                await deliver { onNotice(L10n.f("输入过长，已分 %@ 段处理", String(chunking.chunks.count))) }
            }

            // Matched per chunk, so a long text doesn't send every term with every chunk.
            func glossaryHint(for text: String) -> String? {
                guard mode == .translate else { return nil }
                return GlossaryMatcher.hint(for: GlossaryMatcher.matches(
                    in: text,
                    entries: glossary,
                    targetLanguage: targetLanguage.rawValue
                ))
            }

            let output = try await promptRunner.run(
                template: template,
                chunks: chunking.chunks,
                provider: provider,
                apiKey: apiKey,
                enableStreaming: enableStreaming,
                mode: mode,
                targetLanguage: targetLanguage.promptName,
                glossaryHints: chunking.chunks.map(glossaryHint),
                contextHint: contextHint,
                onActivity: { activity in await deliver { onActivity(activity) } },
                onUpdate: { partial in await deliver { onPartialResult(partial) } }
            )

            let wholeText = chunking.chunks.joined(separator: "\n\n")
            let prompt = promptRunner.transcriptPrompt(
                template: template,
                text: wholeText,
                mode: mode,
                targetLanguage: targetLanguage.promptName,
                glossaryHint: glossaryHint(for: wholeText),
                contextHint: contextHint
            )
            return [
                ConversationMessage(role: .user, content: prompt),
                ConversationMessage(role: .assistant, content: output),
            ]
        }
    }

    /// Asks `question` on top of `history`. On success, `onFinished` receives the answer;
    /// a cancelled run finishes with an empty string.
    func runFollowUp(
        question: String,
        history: [ConversationMessage],
        mode: TranslationMode,
        provider: LLMProvider,
        apiKey: String,
        enableStreaming: Bool,
        onActivity: @escaping (LLMActivity) -> Void,
        onPartialResult: @escaping (String) -> Void,
        onFinished: @escaping (Result<String, Error>) -> Void
    ) {
        launch(onFinished: onFinished, cancelledValue: "") { [promptRunner] deliver in
            try await promptRunner.run(
                template: "{{text}}",
                chunks: [question],
                provider: provider,
                apiKey: apiKey,
                enableStreaming: enableStreaming,
                mode: mode,
                history: history,
                onActivity: { activity in await deliver { onActivity(activity) } },
                onUpdate: { partial in await deliver { onPartialResult(partial) } }
            )
        }
    }

    typealias Deliver = (@MainActor () -> Void) async -> Void

    /// Starts `body` as the only running request. Callbacks from a superseded
    /// request are dropped, so a stale stream never writes into the new run's UI.
    private func launch<Value>(
        onFinished: @escaping (Result<Value, Error>) -> Void,
        cancelledValue: Value,
        _ body: @escaping (_ deliver: @escaping Deliver) async throws -> Value
    ) {
        runGeneration += 1
        let generation = runGeneration
        runningTask?.cancel()
        runningTask = Task {
            defer {
                Task { @MainActor in
                    if self.runGeneration == generation {
                        self.runningTask = nil
                    }
                }
            }

            let deliver: Deliver = { update in
                await self.deliver(generation: generation, update)
            }

            do {
                let value = try await body(deliver)
                await deliver { onFinished(.success(value)) }
            } catch is CancellationError {
                await deliver { onFinished(.success(cancelledValue)) }
            } catch {
                await deliver { onFinished(.failure(error)) }
            }
        }
    }

    private func deliver(generation: Int, _ body: @MainActor () -> Void) async {
        await MainActor.run {
            guard runGeneration == generation else { return }
            body()
        }
    }
}

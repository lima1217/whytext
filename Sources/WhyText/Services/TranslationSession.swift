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

    func run(
        mode: TranslationMode,
        template: String,
        selectedText: String,
        provider: LLMProvider,
        apiKey: String,
        maxInputCharacters: Int,
        splitLongInput: Bool,
        enableStreaming: Bool,
        onNotice: @escaping (String?) -> Void,
        onPartialResult: @escaping (String) -> Void,
        onFinished: @escaping (Result<Void, Error>) -> Void
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

            do {
                let chunking = TextChunker.chunk(
                    text: selectedText,
                    maxCharacters: maxInputCharacters,
                    splitLongInput: splitLongInput
                )

                if chunking.wasTruncated {
                    await deliver(generation: generation) {
                        onNotice("输入过长，已截断到 \(maxInputCharacters) 字符")
                    }
                } else if selectedText.count > maxInputCharacters && chunking.chunks.count > 1 {
                    await deliver(generation: generation) {
                        onNotice("输入过长，已分 \(chunking.chunks.count) 段处理")
                    }
                }

                _ = try await promptRunner.run(
                    template: template,
                    chunks: chunking.chunks,
                    provider: provider,
                    apiKey: apiKey,
                    enableStreaming: enableStreaming,
                    mode: mode,
                    onUpdate: { partial in
                        await self.deliver(generation: generation) {
                            onPartialResult(partial)
                        }
                    }
                )

                await deliver(generation: generation) {
                    onFinished(.success(()))
                }
            } catch is CancellationError {
                await deliver(generation: generation) {
                    onFinished(.success(()))
                }
            } catch {
                await deliver(generation: generation) {
                    onFinished(.failure(error))
                }
            }
        }
    }

    private func deliver(generation: Int, _ body: () -> Void) async {
        await MainActor.run {
            guard runGeneration == generation else { return }
            body()
        }
    }
}

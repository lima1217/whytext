import Foundation
import WhyTextCore

/// Deterministic regression tests for stateful services in `WhyTextApp`.
/// Kept inside the module so they exercise internal state machines directly
/// without requiring `@testable import` or full Xcode / XCTest.
public enum StateMachineSelfTests {
    public static func runAll() async throws {
        try await testLLMClientMapsURLErrorCancelledToCancellationError()
        try await testTranslationSessionCancelModes()
        try await testPromptRunnerSuppressesActivityAfterVisibleText()
        try testDeletedProviderCannotResurrectAPIKey()
        try await testReadingMemoryClearPreventsStaleLoad()
    }

    // MARK: - LLMClient cancellation

    private static func testLLMClientMapsURLErrorCancelledToCancellationError() async throws {
        let session = makeMockSession { _ in
            throw URLError(.cancelled)
        }
        let client = LLMClient(session: session)
        let provider = LLMProvider(
            name: "Test",
            baseURL: "https://example.test",
            model: "test-model",
            apiMode: .chatCompletions
        )

        do {
            _ = try await client.complete(prompt: "hello", provider: provider, apiKey: "sk-test")
            fail("complete() should throw CancellationError when URLSession throws URLError.cancelled")
        } catch is CancellationError {
            // expected
        } catch {
            fail("complete() threw \(error) instead of CancellationError")
        }

        // Stream path: URLError.cancelled finishes cleanly without throwing an LLMError.
        var sawEvent = false
        for try await _ in client.stream(prompt: "hello", provider: provider, apiKey: "sk-test") {
            sawEvent = true
        }
        expect(!sawEvent, "cancelled stream should emit no events")
    }

    // MARK: - TranslationSession cancel(discardCallbacks:)

    @MainActor
    private static func testTranslationSessionCancelModes() async throws {
        let provider = LLMProvider(
            name: "Test",
            baseURL: "https://example.test",
            model: "test-model",
            apiMode: .chatCompletions
        )

        // 1. cancel(discardCallbacks: false) delivers .success([]) (clean stop, no error).
        let stopSession = TranslationSession(promptRunner: PromptRunner(llmClient: LLMClient(session: makeMockSession { _ in
            throw URLError(.cancelled)
        })))

        let stopResult: Result<[ConversationMessage], Error> = await withCheckedContinuation { continuation in
            stopSession.run(
                mode: .translate,
                template: "{{text}}",
                selectedText: "hello",
                targetLanguage: .english,
                provider: provider,
                apiKey: "sk-test",
                maxInputCharacters: 4000,
                splitLongInput: false,
                enableStreaming: false,
                glossary: [],
                contextHint: nil,
                onNotice: { _ in },
                onActivity: { _ in },
                onPartialResult: { _ in },
                onFinished: { result in
                    continuation.resume(returning: result)
                }
            )
            stopSession.cancel(discardCallbacks: false)
        }
        switch stopResult {
        case .success(let messages):
            expect(messages.isEmpty, "cancelled run should finish with empty transcript")
        case .failure(let error):
            fail("cancelled run should not surface failure: \(error)")
        }

        // 2. cancel(discardCallbacks: true) suppresses late onFinished callbacks completely.
        let discardSession = TranslationSession(promptRunner: PromptRunner(llmClient: LLMClient(session: makeMockSession { _ in
            Thread.sleep(forTimeInterval: 0.05)
            let body = #"{"choices":[{"message":{"role":"assistant","content":"hi"}}]}"#
            return (200, Data(body.utf8))
        })))

        var callbackFired = false
        discardSession.run(
            mode: .translate,
            template: "{{text}}",
            selectedText: "hello",
            targetLanguage: .english,
            provider: provider,
            apiKey: "sk-test",
            maxInputCharacters: 4000,
            splitLongInput: false,
            enableStreaming: false,
            glossary: [],
            contextHint: nil,
            onNotice: { _ in callbackFired = true },
            onActivity: { _ in callbackFired = true },
            onPartialResult: { _ in callbackFired = true },
            onFinished: { _ in callbackFired = true }
        )
        discardSession.cancel(discardCallbacks: true)
        try await Task.sleep(nanoseconds: 120_000_000)
        expect(!callbackFired, "cancel(discardCallbacks: true) must drop all stale callbacks")
    }

    // MARK: - PromptRunner ChunkProgress ordering

    private static func testPromptRunnerSuppressesActivityAfterVisibleText() async throws {
        let sse = [
            #"data: {"choices":[{"delta":{"reasoning_content":"step 1"}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"reasoning_content":"late thinking"}}]}"#,
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")

        let session = makeMockSession { _ in
            (200, Data(sse.utf8))
        }
        let runner = PromptRunner(llmClient: LLMClient(session: session))
        let provider = LLMProvider(
            name: "Test",
            baseURL: "https://example.test",
            model: "test-model",
            apiMode: .chatCompletions
        )

        final class EventLog: @unchecked Sendable {
            private let lock = NSLock()
            var entries: [String] = []
            func append(_ entry: String) {
                lock.lock()
                entries.append(entry)
                lock.unlock()
            }
        }
        let log = EventLog()

        let output = try await runner.run(
            template: "{{text}}",
            chunks: ["hi"],
            provider: provider,
            apiKey: "sk-test",
            enableStreaming: true,
            mode: .explain,
            onActivity: { activity in
                log.append("activity:\(activity)")
            },
            onUpdate: { partial in
                log.append("text:\(partial)")
            }
        )

        expect(output == "Hello", "expected Hello, got \(output)")
        expect(log.entries == ["activity:thinking", "text:Hello"], "late activity after visible text must be suppressed, got \(log.entries)")
    }

    // MARK: - SettingsStore deleted provider API key non-resurrection

    private static func testDeletedProviderCannotResurrectAPIKey() throws {
        let suiteName = "com.whytext.state-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = APIKeychainStore(service: suiteName)
        let store = SettingsStore(apiKeychainStore: keychain, userDefaults: defaults)
        store.addProvider()
        guard let addedID = store.selectedProviderID else {
            fail("addProvider should select the new provider")
            return
        }
        defer { _ = keychain.deleteAPIKey(for: addedID) }

        store.saveAPIKey("sk-secret-123", for: addedID)
        expect(store.apiKey(for: addedID) == "sk-secret-123", "saved API key should be readable")

        store.removeProviders(withIDs: [addedID])
        expect(store.apiKey(for: addedID).isEmpty, "removed provider's API key should be deleted")

        // Simulate SwiftUI onDisappear trying to flush apiKeyDraft after removal.
        store.saveAPIKey("sk-secret-123", for: addedID)
        expect(store.apiKey(for: addedID).isEmpty, "saveAPIKey must not resurrect a removed provider's key")
    }

    // MARK: - ReadingMemoryStore clearAll vs in-flight disk load

    @MainActor
    private static func testReadingMemoryClearPreventsStaleLoad() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whytext-memory-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = LookupRecord(
            date: Date(),
            sessionID: UUID(),
            action: "translate",
            input: .selection,
            sourceText: "hello",
            resultText: "你好",
            targetLanguage: "zh-Hans",
            source: LookupSource()
        )
        let line = try LookupLog.encodeLine(record)
        try line.write(to: dir.appendingPathComponent("lookups.jsonl"))

        let store = ReadingMemoryStore(directory: dir)
        store.clearAll()
        try await Task.sleep(nanoseconds: 100_000_000)
        expect(store.recordCount == 0, "clearAll() must prevent in-flight disk load from restoring cleared records")
    }

    // MARK: - Helpers

    private static func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)
    ) -> URLSession {
        let id = UUID().uuidString
        MockURLProtocol.register(id: id, handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = ["X-WhyText-Mock-ID": id]
        return URLSession(configuration: config)
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fail(message)
        }
    }

    private static func fail(_ message: String) {
        fputs("StateMachineSelfTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) throws -> (Int, Data)] = [:]

    static func register(id: String, handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.lock()
        handlers[id] = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-WhyText-Mock-ID") ?? ""
        Self.lock.lock()
        let handler = Self.handlers[id]
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

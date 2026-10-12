import Foundation
import WhyTextCore

enum TranslationMode: String, Codable {
    case translate
    case explain
}

enum TranslationErrorCode: String, Codable {
    case unauthorized
    case rateLimited
    case timeout
    case noPermission
    case network
    case emptyResponse
    case invalidResponse
    case invalidBaseURL
    case unknown
}

/// One prior turn of a conversation, replayed ahead of a follow-up question.
struct ConversationMessage: Equatable {
    enum Role: String {
        case user
        case assistant
    }

    var role: Role
    var content: String
}

struct UnifiedTranslationRequest {
    var model: String
    var sourceText: String
    var sourceLanguage: String
    var targetLanguage: String
    var mode: TranslationMode
    var promptTemplate: String
    var stream: Bool
    var includeStructureHint: Bool = true
    /// Ask the provider to run server-side web search when it supports it.
    var enableWebSearch: Bool = false
    /// Earlier turns sent before this request's prompt (follow-up questions).
    var history: [ConversationMessage] = []

    /// The default explain prompt's search sentence. Providers without
    /// server-side search get it stripped so the model never pretends to search.
    static let webSearchInstruction = "拿不准的专名、术语或背景，先搜索，拿到更精确的上下文再解释；搜完仍存疑的，照旧标成不确定。"

    func renderedPrompt(supportsWebSearch: Bool) -> String {
        let basePrompt: String

        // Substitute {{target}} first so a literal "{{target}}" in the source text survives.
        let template = promptTemplate.replacingOccurrences(of: "{{target}}", with: targetLanguage)

        if template.contains("{{text}}") {
            basePrompt = template.replacingOccurrences(of: "{{text}}", with: sourceText)
        } else {
            let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                basePrompt = sourceText
            } else {
                basePrompt = "\(trimmed)\n\n\(sourceText)"
            }
        }

        let prompt = supportsWebSearch && enableWebSearch
            ? basePrompt
            : basePrompt
                .replacingOccurrences(of: Self.webSearchInstruction + "\n\n", with: "")
                .replacingOccurrences(of: Self.webSearchInstruction, with: "")

        guard includeStructureHint else {
            return prompt
        }

        return "\(Self.structureHint)\n\n\(prompt)"
    }

    private static let structureHint = "保持原文段落结构：原文分几段，译文也分几段；不要合并段落。"
}

struct UnifiedTranslationResponse {
    var model: String
    var sourceText: String
    var sourceLanguage: String
    var targetLanguage: String
    var mode: TranslationMode
    var translatedText: String
    var errorCode: TranslationErrorCode?
}

final class LLMClient {
    private let session: URLSession
    private let allowsTransientRetry: Bool
    /// Provider/model pairs that rejected optional parameters with HTTP 400.
    private var minimalParameterKeys = Set<String>()
    private let minimalParametersLock = NSLock()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            self.allowsTransientRetry = false
        } else {
            self.session = Self.makeURLSession()
            self.allowsTransientRetry = true
        }
    }

    func complete(prompt: String, provider: LLMProvider, apiKey: String) async throws -> String {
        let request = UnifiedTranslationRequest(
            model: provider.model,
            sourceText: prompt,
            sourceLanguage: "auto",
            targetLanguage: "auto",
            mode: .translate,
            promptTemplate: "{{text}}",
            stream: false,
            includeStructureHint: false
        )

        let response = try await complete(request: request, provider: provider, apiKey: apiKey)
        return response.translatedText
    }

    func complete(request: UnifiedTranslationRequest, provider: LLMProvider, apiKey: String) async throws -> UnifiedTranslationResponse {
        do {
            let adapter = ProviderAdapter(mode: provider.apiMode)
            let url = try adapter.endpointURL(baseURL: provider.baseURL)
            let makeHTTPRequest = { (minimal: Bool) throws -> URLRequest in
                var httpRequest = self.makeRequest(url: url, apiKey: apiKey)
                httpRequest.httpBody = try adapter.requestBody(
                    from: request,
                    stream: false,
                    baseURL: provider.baseURL,
                    minimal: minimal
                )
                return httpRequest
            }

            let key = parameterCompatibilityKey(provider)
            let startMinimal = usesMinimalParameters(key)
            var (data, response) = try await performDataRequest(makeHTTPRequest(startMinimal))
            try Task.checkCancellation()

            // Optional knobs (temperature, reasoning, thinking, tools) are rejected
            // by some models and proxies. Retry once without them and remember.
            if !startMinimal, (response as? HTTPURLResponse)?.statusCode == 400 {
                (data, response) = try await performDataRequest(makeHTTPRequest(true))
                try Task.checkCancellation()
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    markUsesMinimalParameters(key)
                }
            }

            guard let http = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse
            }

            guard (200..<300).contains(http.statusCode) else {
                throw mapRemoteError(statusCode: http.statusCode, body: data)
            }

            let text = try adapter.parseCompletionText(from: data)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                throw LLMError.emptyOutput
            }

            return UnifiedTranslationResponse(
                model: request.model,
                sourceText: request.sourceText,
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage,
                mode: request.mode,
                translatedText: trimmed,
                errorCode: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LLMError {
            throw error
        } catch {
            throw mapTransportError(error)
        }
    }

    func stream(prompt: String, provider: LLMProvider, apiKey: String) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let request = UnifiedTranslationRequest(
            model: provider.model,
            sourceText: prompt,
            sourceLanguage: "auto",
            targetLanguage: "auto",
            mode: .translate,
            promptTemplate: "{{text}}",
            stream: true,
            includeStructureHint: false
        )

        return stream(request: request, provider: provider, apiKey: apiKey)
    }

    func stream(request: UnifiedTranslationRequest, provider: LLMProvider, apiKey: String) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let adapter = ProviderAdapter(mode: provider.apiMode)
                    let url = try adapter.endpointURL(baseURL: provider.baseURL)
                    let makeHTTPRequest = { (minimal: Bool) throws -> URLRequest in
                        var httpRequest = self.makeRequest(url: url, apiKey: apiKey)
                        httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        httpRequest.httpBody = try adapter.requestBody(
                            from: request,
                            stream: true,
                            baseURL: provider.baseURL,
                            minimal: minimal
                        )
                        return httpRequest
                    }

                    let key = parameterCompatibilityKey(provider)
                    let startMinimal = usesMinimalParameters(key)
                    var (bytes, response) = try await session.bytes(for: makeHTTPRequest(startMinimal))
                    try Task.checkCancellation()

                    var usedMinimal = startMinimal
                    if !startMinimal, (response as? HTTPURLResponse)?.statusCode == 400 {
                        bytes.task.cancel()
                        usedMinimal = true
                        (bytes, response) = try await session.bytes(for: makeHTTPRequest(true))
                        try Task.checkCancellation()
                        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                            markUsesMinimalParameters(key)
                        }
                    }

                    // Same one-shot gateway retry as the non-streaming path.
                    if allowsTransientRetry,
                       let status = (response as? HTTPURLResponse)?.statusCode,
                       Self.transientStatusCodes.contains(status) {
                        bytes.task.cancel()
                        try await Task.sleep(nanoseconds: 250_000_000)
                        (bytes, response) = try await session.bytes(for: makeHTTPRequest(usedMinimal))
                        try Task.checkCancellation()
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.invalidResponse
                    }

                    guard (200..<300).contains(http.statusCode) else {
                        let data = try await readAll(bytes: bytes, upTo: 64 * 1024)
                        throw mapRemoteError(statusCode: http.statusCode, body: data)
                    }

                    var parser = SSEEventParser()
                    var isDone = false

                    byteLoop: for try await byte in bytes {
                        try Task.checkCancellation()

                        let events = parser.append(byte: byte)
                        for event in events {
                            if event.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                                isDone = true
                                break byteLoop
                            }

                            guard let jsonData = event.data.data(using: .utf8) else { continue }
                            if let streamEvent = try adapter.parseStreamEvent(from: jsonData) {
                                continuation.yield(streamEvent)
                            }
                        }
                    }

                    if !isDone {
                        for event in parser.finish() {
                            if event.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                                break
                            }

                            guard let jsonData = event.data.data(using: .utf8) else { continue }
                            if let streamEvent = try adapter.parseStreamEvent(from: jsonData) {
                                continuation.yield(streamEvent)
                            }
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: mapTransportError(error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static let transientStatusCodes: Set<Int> = [502, 503, 504]

    private func parameterCompatibilityKey(_ provider: LLMProvider) -> String {
        "\(provider.apiMode)|\(provider.baseURL)|\(provider.model)"
    }

    private func usesMinimalParameters(_ key: String) -> Bool {
        minimalParametersLock.lock()
        defer { minimalParametersLock.unlock() }
        return minimalParameterKeys.contains(key)
    }

    private func markUsesMinimalParameters(_ key: String) {
        minimalParametersLock.lock()
        minimalParameterKeys.insert(key)
        minimalParametersLock.unlock()
    }

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)

        guard allowsTransientRetry,
              let http = response as? HTTPURLResponse,
              Self.transientStatusCodes.contains(http.statusCode) else {
            return (data, response)
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        return try await session.data(for: request)
    }

    private static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        // Fail fast when offline instead of silently waiting out the resource timeout.
        configuration.waitsForConnectivity = false
        // Per-packet idle limit; reasoning or search can stall the stream for a while.
        configuration.timeoutIntervalForRequest = 90
        // Whole-response cap, streaming included. Explain runs high-effort
        // reasoning plus web search and can legitimately take several minutes.
        configuration.timeoutIntervalForResource = 300
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }

    private func mapRemoteError(statusCode: Int, body: Data) -> LLMError {
        let message = parseErrorMessage(from: body)

        switch statusCode {
        case 401:
            return .remoteError(code: .unauthorized, statusCode: statusCode, message: message)
        case 403:
            return .remoteError(code: .noPermission, statusCode: statusCode, message: message)
        case 408, 504:
            return .remoteError(code: .timeout, statusCode: statusCode, message: message)
        case 429:
            return .remoteError(code: .rateLimited, statusCode: statusCode, message: message)
        case 502, 503:
            return .remoteError(code: .unknown, statusCode: statusCode, message: message ?? "上游服务暂时不可用，请稍后重试。如使用代理，请检查 Base URL 是否正确。")
        default:
            return .remoteError(code: .unknown, statusCode: statusCode, message: message)
        }
    }

    private func mapTransportError(_ error: Error) -> LLMError {
        if let llmError = error as? LLMError {
            return llmError
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .transportError(code: .timeout, message: urlError.localizedDescription)
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return .transportError(code: .network, message: urlError.localizedDescription)
            default:
                return .transportError(code: .unknown, message: urlError.localizedDescription)
            }
        }

        return .transportError(code: .unknown, message: error.localizedDescription)
    }
}

enum LLMError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case emptyOutput
    case remoteError(code: TranslationErrorCode, statusCode: Int, message: String?)
    case transportError(code: TranslationErrorCode, message: String?)
    /// The provider reported a failure inside an otherwise successful stream.
    case streamError(message: String)

    var errorCode: TranslationErrorCode {
        switch self {
        case .invalidBaseURL:
            .invalidBaseURL
        case .invalidResponse:
            .invalidResponse
        case .emptyOutput:
            .emptyResponse
        case .remoteError(let code, _, _):
            code
        case .transportError(let code, _):
            code
        case .streamError:
            .unknown
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Provider Base URL 不合法"
        case .invalidResponse:
            "响应格式不正确，请重试"
        case .emptyOutput:
            "模型未返回内容，请重试"
        case .remoteError(let code, _, _), .transportError(let code, _):
            Self.localizedMessage(for: code)
        case .streamError(let message):
            "模型返回错误：\(message)"
        }
    }

    var failureReason: String? {
        switch self {
        case .remoteError(_, let statusCode, let message):
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "HTTP \(statusCode): \(message)"
            }
            return "HTTP \(statusCode)"
        case .transportError(_, let message):
            return message
        default:
            return nil
        }
    }

    /// Whether a failed streaming request may safely retry once without streaming.
    /// Auth, rate limits, timeouts, and hard transport failures should not double-hit the API.
    var shouldAttemptNonStreamingFallback: Bool {
        switch self {
        case .invalidResponse, .emptyOutput:
            return true
        case .remoteError(let code, let statusCode, _):
            switch code {
            case .unauthorized, .rateLimited, .noPermission, .timeout:
                return false
            case .invalidBaseURL, .network, .emptyResponse, .invalidResponse, .unknown:
                return [400, 404, 415, 422].contains(statusCode)
            }
        case .invalidBaseURL, .transportError, .streamError:
            return false
        }
    }

    private static func localizedMessage(for code: TranslationErrorCode) -> String {
        switch code {
        case .unauthorized:
            return "API Key 无效或已过期（401）"
        case .rateLimited:
            return "请求过于频繁，请稍后重试（429）"
        case .timeout:
            return "网络超时，请检查网络后重试"
        case .noPermission:
            return "无权限访问该模型或接口（403）"
        case .network:
            return "网络异常，请检查连接后重试"
        case .emptyResponse:
            return "模型未返回内容，请重试"
        case .invalidResponse:
            return "响应格式不正确，请重试"
        case .invalidBaseURL:
            return "Provider Base URL 不合法"
        case .unknown:
            return "请求失败，请稍后重试"
        }
    }
}

private enum ProviderAdapter {
    case chatCompletions
    case responses

    init(mode: LLMAPIMode) {
        switch mode {
        case .chatCompletions:
            self = .chatCompletions
        case .responses:
            self = .responses
        }
    }

    func endpointURL(baseURL: String) throws -> URL {
        do {
            return try ProviderEndpointBuilder.endpointURL(baseURL: baseURL, resourcePath: resourcePath)
        } catch {
            throw LLMError.invalidBaseURL
        }
    }

    private var resourcePath: String {
        switch self {
        case .chatCompletions:
            "chat/completions"
        case .responses:
            "responses"
        }
    }

    /// `minimal` drops every optional knob for models or proxies that reject them.
    func requestBody(from request: UnifiedTranslationRequest, stream: Bool, baseURL: String, minimal: Bool = false) throws -> Data {
        if minimal {
            switch self {
            case .chatCompletions:
                let body = ChatCompletionsRequest(
                    model: request.model,
                    messages: Self.chatMessages(for: request),
                    stream: stream
                )
                return try JSONEncoder().encode(body)
            case .responses:
                let body = ResponsesRequest(
                    model: request.model,
                    input: Self.responsesInput(for: request, supportsWebSearch: false),
                    stream: stream
                )
                return try JSONEncoder().encode(body)
            }
        }

        switch self {
        case .chatCompletions:
            // DeepSeek thinking defaults to enabled and slows translation; turn it
            // off for translation. The chat endpoint's knob is binary, so keep it
            // enabled for explanation instead of an effort level.
            let thinking: ThinkingConfig?
            if Self.supportsThinkingToggle(baseURL: baseURL) {
                thinking = ThinkingConfig(type: request.mode == .explain ? "enabled" : "disabled")
            } else {
                thinking = nil
            }
            let body = ChatCompletionsRequest(
                model: request.model,
                messages: Self.chatMessages(for: request),
                temperature: 0.2,
                stream: stream,
                thinking: thinking
            )
            return try JSONEncoder().encode(body)
        case .responses:
            // Translation is latency-sensitive and needs no reasoning; explanation
            // benefits from deeper thinking, so give it a high effort budget.
            let effort = request.mode == .explain ? "high" : "none"
            let body = ResponsesRequest(
                model: request.model,
                input: Self.responsesInput(for: request, supportsWebSearch: true),
                stream: stream,
                reasoning: ReasoningConfig(effort: effort),
                tools: request.enableWebSearch ? [ResponsesTool(type: "web_search")] : nil
            )
            return try JSONEncoder().encode(body)
        }
    }

    private static func chatMessages(for request: UnifiedTranslationRequest) -> [ChatMessage] {
        request.history.map { ChatMessage(role: $0.role.rawValue, content: $0.content) }
            + [ChatMessage(role: "user", content: request.renderedPrompt(supportsWebSearch: false))]
    }

    private static func responsesInput(for request: UnifiedTranslationRequest, supportsWebSearch: Bool) -> ResponsesInput {
        let prompt = request.renderedPrompt(supportsWebSearch: supportsWebSearch)
        guard !request.history.isEmpty else {
            return .text(prompt)
        }
        return .messages(
            request.history.map { ChatMessage(role: $0.role.rawValue, content: $0.content) }
                + [ChatMessage(role: "user", content: prompt)]
        )
    }

    private static func supportsThinkingToggle(baseURL: String) -> Bool {
        baseURL.lowercased().contains("deepseek")
    }

    func parseCompletionText(from data: Data) throws -> String {
        switch self {
        case .chatCompletions:
            let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
            guard let text = decoded.choices.first?.message.content,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.emptyOutput
            }
            return text
        case .responses:
            if let decoded = try? JSONDecoder().decode(ResponsesResponse.self, from: data),
               let text = decoded.bestEffortText(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }

            if let text = bestEffortText(from: data),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }

            throw LLMError.emptyOutput
        }
    }

    /// Throws `LLMError.streamError` when the provider reports a failure in-band.
    func parseStreamEvent(from data: Data) throws -> LLMStreamEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        do {
            switch self {
            case .chatCompletions:
                return try LLMStreamEventParser.chatCompletionsEvent(from: json)
            case .responses:
                return try LLMStreamEventParser.responsesEvent(from: json)
            }
        } catch let error as LLMStreamProviderError {
            throw LLMError.streamError(message: error.message)
        }
    }
}

private func parseErrorMessage(from data: Data) -> String? {
    struct WrappedError: Decodable {
        struct Inner: Decodable {
            var message: String?
        }

        var error: Inner?
        var message: String?
    }

    if let decoded = try? JSONDecoder().decode(WrappedError.self, from: data) {
        return decoded.error?.message ?? decoded.message
    }

    return String(data: data, encoding: .utf8)
}

private struct ThinkingConfig: Encodable {
    var type: String
}

private struct ReasoningConfig: Encodable {
    var effort: String
}

private struct ChatCompletionsRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double?
    var stream: Bool?
    var thinking: ThinkingConfig?
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        var message: ChatMessage
    }

    var choices: [Choice]
}

/// Responses API `input`: a bare prompt, or role-tagged messages for multi-turn.
private enum ResponsesInput: Encodable {
    case text(String)
    case messages([ChatMessage])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .messages(let messages):
            try container.encode(messages)
        }
    }
}

private struct ResponsesRequest: Encodable {
    var model: String
    var input: ResponsesInput
    var stream: Bool?
    var reasoning: ReasoningConfig?
    var tools: [ResponsesTool]?
}

private struct ResponsesTool: Encodable {
    var type: String
}

private func readAll(bytes: URLSession.AsyncBytes, upTo limit: Int) async throws -> Data {
    var data = Data()
    data.reserveCapacity(min(limit, 8 * 1024))

    for try await byte in bytes {
        data.append(byte)
        if data.count >= limit {
            break
        }
    }

    return data
}

private struct ResponsesResponse: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            var type: String?
            var text: String?
        }

        var type: String?
        var content: [ContentItem]?
    }

    var output_text: String?
    var output: [OutputItem]?

    func bestEffortText() -> String? {
        if let output_text {
            return output_text
        }

        for item in output ?? [] {
            for content in item.content ?? [] {
                let type = content.type
                if (type == "output_text" || type == "text"), let text = content.text {
                    return text
                }
            }
        }

        return nil
    }
}

private func bestEffortText(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    if let outputText = json["output_text"] as? String {
        return outputText
    }

    if let output = json["output"] as? [[String: Any]] {
        for item in output {
            if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    let type = part["type"] as? String
                    if (type == "output_text" || type == "text"), let text = part["text"] as? String {
                        return text
                    }
                }
            }
        }
    }

    return nil
}

import Foundation

enum TranslationMode: String, Codable {
    case translate
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

struct UnifiedTranslationRequest {
    static let defaultDeviceDescriptor = "\(ProcessInfo.processInfo.hostName) / \(ProcessInfo.processInfo.operatingSystemVersionString)"

    var model: String
    var sourceText: String
    var sourceLanguage: String
    var targetLanguage: String
    var mode: TranslationMode
    var device: String
    var promptTemplate: String
    var stream: Bool
    var includeStructureHint: Bool = true

    var renderedPrompt: String {
        let basePrompt: String

        if promptTemplate.contains("{{text}}") {
            basePrompt = promptTemplate.replacingOccurrences(of: "{{text}}", with: sourceText)
        } else {
            let trimmed = promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                basePrompt = sourceText
            } else {
                basePrompt = "\(trimmed)\n\n\(sourceText)"
            }
        }

        guard includeStructureHint else {
            return basePrompt
        }

        return "\(Self.structureHint)\n\n\(basePrompt)"
    }

    private static let structureHint = "保持原文段落结构：原文分几段，译文也分几段；不要合并段落。"
}

struct UnifiedTranslationResponse {
    var model: String
    var sourceText: String
    var sourceLanguage: String
    var targetLanguage: String
    var mode: TranslationMode
    var device: String
    var translatedText: String
    var errorCode: TranslationErrorCode?
}

final class LLMClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(prompt: String, provider: LLMProvider, apiKey: String) async throws -> String {
        let request = UnifiedTranslationRequest(
            model: provider.model,
            sourceText: prompt,
            sourceLanguage: "auto",
            targetLanguage: "auto",
            mode: .translate,
            device: UnifiedTranslationRequest.defaultDeviceDescriptor,
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
            var httpRequest = makeRequest(url: url, apiKey: apiKey)
            httpRequest.httpBody = try adapter.requestBody(from: request, stream: false)

            let (data, response) = try await session.data(for: httpRequest)
            try Task.checkCancellation()

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
                device: request.device,
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

    func stream(prompt: String, provider: LLMProvider, apiKey: String) -> AsyncThrowingStream<String, Error> {
        let request = UnifiedTranslationRequest(
            model: provider.model,
            sourceText: prompt,
            sourceLanguage: "auto",
            targetLanguage: "auto",
            mode: .translate,
            device: UnifiedTranslationRequest.defaultDeviceDescriptor,
            promptTemplate: "{{text}}",
            stream: true,
            includeStructureHint: false
        )

        return stream(request: request, provider: provider, apiKey: apiKey)
    }

    func stream(request: UnifiedTranslationRequest, provider: LLMProvider, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let adapter = ProviderAdapter(mode: provider.apiMode)
                    let url = try adapter.endpointURL(baseURL: provider.baseURL)
                    var httpRequest = makeRequest(url: url, apiKey: apiKey)
                    httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    httpRequest.httpBody = try adapter.requestBody(from: request, stream: true)

                    let (bytes, response) = try await session.bytes(for: httpRequest)
                    try Task.checkCancellation()

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
                            if let delta = adapter.parseStreamDelta(from: jsonData), !delta.isEmpty {
                                continuation.yield(delta)
                            }
                        }
                    }

                    if !isDone {
                        for event in parser.finish() {
                            if event.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                                break
                            }

                            guard let jsonData = event.data.data(using: .utf8) else { continue }
                            if let delta = adapter.parseStreamDelta(from: jsonData), !delta.isEmpty {
                                continuation.yield(delta)
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

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
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
        let rawBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBaseURL.isEmpty else { throw LLMError.invalidBaseURL }

        var base = rawBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Strip known endpoint suffixes so users can paste full URLs.
        let knownSuffixes = [
            "/v1/chat/completions",
            "/v1/responses",
            "/chat/completions",
            "/responses",
        ]
        for suffix in knownSuffixes {
            if base.lowercased().hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                break
            }
        }

        let resourcePath: String
        switch self {
        case .chatCompletions:
            resourcePath = "chat/completions"
        case .responses:
            resourcePath = "responses"
        }

        let path = base.hasSuffix("/v1") ? resourcePath : "v1/\(resourcePath)"
        let urlString = "\(base)/\(path)"

        guard let url = URL(string: urlString) else {
            throw LLMError.invalidBaseURL
        }

        return url
    }

    func requestBody(from request: UnifiedTranslationRequest, stream: Bool) throws -> Data {
        switch self {
        case .chatCompletions:
            let body = ChatCompletionsRequest(
                model: request.model,
                messages: [ChatMessage(role: "user", content: request.renderedPrompt)],
                temperature: 0.2,
                stream: stream
            )
            return try JSONEncoder().encode(body)
        case .responses:
            let body = ResponsesRequest(
                model: request.model,
                input: request.renderedPrompt,
                stream: stream
            )
            return try JSONEncoder().encode(body)
        }
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

    func parseStreamDelta(from data: Data) -> String? {
        switch self {
        case .chatCompletions:
            guard let chunk = try? JSONDecoder().decode(ChatCompletionsStreamChunk.self, from: data) else {
                return nil
            }
            return chunk.choices.first?.delta.content
        case .responses:
            return parseResponsesDelta(from: data)
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

private struct ChatCompletionsRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double?
    var stream: Bool?
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

private struct ResponsesRequest: Encodable {
    var model: String
    var input: String
    var stream: Bool?
}

private struct ChatCompletionsStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }

        var delta: Delta
    }

    var choices: [Choice]
}

private struct SSEEvent {
    var event: String?
    var data: String
    var id: String?
}

private struct SSEEventParser {
    private var lineBuffer: [UInt8] = []
    private var dataLines: [String] = []
    private var eventType: String?
    private var lastEventID: String?
    private var isFirstLine = true
    private var lastByteWasCR = false

    mutating func append(byte: UInt8) -> [SSEEvent] {
        if byte == 0x0D {
            let events = processLine()
            lastByteWasCR = true
            return events
        }

        if byte == 0x0A {
            if lastByteWasCR {
                lastByteWasCR = false
                return []
            }
            return processLine()
        }

        lastByteWasCR = false
        lineBuffer.append(byte)
        return []
    }

    mutating func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []

        if !lineBuffer.isEmpty {
            events.append(contentsOf: processLine())
        }

        if let event = emitEventIfNeeded() {
            events.append(event)
        }

        return events
    }

    private mutating func processLine() -> [SSEEvent] {
        var line = String(decoding: lineBuffer, as: UTF8.self)
        lineBuffer.removeAll(keepingCapacity: true)

        if isFirstLine {
            isFirstLine = false
            if line.hasPrefix("\u{FEFF}") {
                line.removeFirst()
            }
        }

        if line.isEmpty {
            if let event = emitEventIfNeeded() {
                return [event]
            }
            return []
        }

        if line.hasPrefix(":") {
            return []
        }

        let field: Substring
        var value: Substring = ""

        if let separator = line.firstIndex(of: ":") {
            field = line[..<separator]
            value = line[line.index(after: separator)...]
            if value.first == " " {
                value.removeFirst()
            }
        } else {
            field = Substring(line)
        }

        switch field {
        case "data":
            dataLines.append(String(value))
        case "event":
            eventType = String(value)
        case "id":
            if !value.contains("\0") {
                lastEventID = String(value)
            }
        case "retry":
            break
        default:
            break
        }

        return []
    }

    private mutating func emitEventIfNeeded() -> SSEEvent? {
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventType = nil
        }

        guard !dataLines.isEmpty else {
            return nil
        }

        return SSEEvent(
            event: eventType?.isEmpty == true ? nil : eventType,
            data: dataLines.joined(separator: "\n"),
            id: lastEventID
        )
    }
}

private func parseResponsesDelta(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    if let type = json["type"] as? String,
       type.contains("output_text"),
       let delta = json["delta"] as? String {
        return delta
    }

    if let delta = json["delta"] as? String {
        return delta
    }

    return nil
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
                if let text = content.text {
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
                    if let text = part["text"] as? String {
                        return text
                    }
                }
            }
        }
    }

    return nil
}

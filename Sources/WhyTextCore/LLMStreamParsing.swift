import Foundation

/// What the model is doing before (or between) visible text.
public enum LLMActivity: Equatable {
    case thinking
    case searching
}

public enum LLMStreamEvent: Equatable {
    case text(String)
    case activity(LLMActivity)
}

/// A failure the provider reported inside an otherwise successful stream.
public struct LLMStreamProviderError: Error, Equatable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

/// Maps one decoded SSE `data:` JSON payload to a stream event.
public enum LLMStreamEventParser {
    public static func chatCompletionsEvent(from json: [String: Any]) throws -> LLMStreamEvent? {
        if let error = json["error"], !(error is NSNull) {
            throw LLMStreamProviderError(message: streamErrorMessage(error))
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }

        if let content = delta["content"] as? String, !content.isEmpty {
            return .text(content)
        }
        // DeepSeek and other reasoning models stream their thinking separately.
        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            return .activity(.thinking)
        }
        return nil
    }

    public static func responsesEvent(from json: [String: Any]) throws -> LLMStreamEvent? {
        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "error":
            throw LLMStreamProviderError(message: streamErrorMessage(json["error"] ?? json["message"] ?? json))
        case "response.failed":
            let response = json["response"] as? [String: Any]
            let detail = response?["error"] ?? response?["incomplete_details"] ?? type
            throw LLMStreamProviderError(message: streamErrorMessage(detail))
        case "response.output_item.added":
            let itemType = (json["item"] as? [String: Any])?["type"] as? String
            if itemType == "reasoning" { return .activity(.thinking) }
            if itemType == "web_search_call" { return .activity(.searching) }
            return nil
        default:
            break
        }

        if type.contains("output_text"), let delta = json["delta"] as? String, !delta.isEmpty {
            return .text(delta)
        }
        if type.hasPrefix("response.web_search_call") {
            return .activity(.searching)
        }
        if type.hasPrefix("response.reasoning") {
            return .activity(.thinking)
        }
        return nil
    }

    private static func streamErrorMessage(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            if let message = dict["message"] as? String { return message }
            if let reason = dict["reason"] as? String { return reason }
            if let code = dict["code"] as? String { return code }
        }
        if let string = value as? String { return string }
        return String(describing: value)
    }
}

public struct SSEEvent: Equatable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental byte-level parser for `text/event-stream` bodies.
public struct SSEEventParser {
    public init() {}

    private var lineBuffer: [UInt8] = []
    private var dataLines: [String] = []
    private var eventType: String?
    private var lastEventID: String?
    private var isFirstLine = true
    private var lastByteWasCR = false

    public mutating func append(byte: UInt8) -> [SSEEvent] {
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

    public mutating func finish() -> [SSEEvent] {
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

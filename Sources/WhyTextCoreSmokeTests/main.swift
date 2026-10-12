import Foundation
import WhyTextCore

@main
enum WhyTextCoreSmokeTests {
    static func main() throws {
        try testProviderEndpointBuilder()
        testCJKLatinSpacer()
        testTextChunker()
        testAccessibilitySelectionHelpers()
        testSelectionAutoPopupPolicy()
        testSSEEventParser()
        testLLMStreamEventParser()
        print("WhyTextCore smoke tests passed")
    }

    private static func testProviderEndpointBuilder() throws {
        let deepSeekURL = try ProviderEndpointBuilder.endpointURL(
            baseURL: "https://api.deepseek.com",
            resourcePath: "chat/completions"
        )
        expect(deepSeekURL.absoluteString == "https://api.deepseek.com/v1/chat/completions", "bare provider base should get v1 path")

        let zAIV4URL = try ProviderEndpointBuilder.endpointURL(
            baseURL: "https://api.z.ai/api/coding/paas/v4",
            resourcePath: "chat/completions"
        )
        expect(zAIV4URL.absoluteString == "https://api.z.ai/api/coding/paas/v4/chat/completions", "versioned base should not get extra v1 path")

        let zAIV5URL = try ProviderEndpointBuilder.endpointURL(
            baseURL: "https://api.z.ai/api/coding/paas/v5/",
            resourcePath: "chat/completions"
        )
        expect(zAIV5URL.absoluteString == "https://api.z.ai/api/coding/paas/v5/chat/completions", "future versioned base should not get extra v1 path")

        let fullEndpointURL = try ProviderEndpointBuilder.endpointURL(
            baseURL: "https://api.z.ai/api/coding/paas/v4/chat/completions",
            resourcePath: "chat/completions"
        )
        expect(fullEndpointURL.absoluteString == "https://api.z.ai/api/coding/paas/v4/chat/completions", "full endpoint should be used as-is")

        let responsesURL = try ProviderEndpointBuilder.endpointURL(
            baseURL: "https://api.example.com/custom/v2025",
            resourcePath: "responses"
        )
        expect(responsesURL.absoluteString == "https://api.example.com/custom/v2025/responses", "responses should follow the same versioned base rule")
    }

    private static func testCJKLatinSpacer() {
        expect(CJKLatinSpacer.apply(toPlainText: "WhyText很好") == "WhyText 很好", "Latin-Chinese spacing")
        expect(CJKLatinSpacer.apply(toPlainText: "使用APIKey字段") == "使用 APIKey 字段", "Chinese-Latin-Chinese spacing")
        expect(CJKLatinSpacer.apply(toPlainText: "`API字段`很好") == "`API字段`很好", "inline code should not be changed")

        let input = """
        ```
        API字段
        ```
        WhyText很好
        """

        let expected = """
        ```
        API字段
        ```
        WhyText 很好
        """

        expect(CJKLatinSpacer.apply(toPlainText: input) == expected, "fenced code should be skipped and spacing should resume")
    }

    private static func testTextChunker() {
        let truncated = TextChunker.chunk(text: "abcdef", maxCharacters: 3, splitLongInput: false)
        expect(truncated.chunks == ["abc"], "disabled splitting should truncate")
        expect(truncated.wasTruncated, "disabled splitting should mark truncation")

        let paragraphs = TextChunker.chunk(text: "first\n\nsecond", maxCharacters: 100, splitLongInput: true)
        expect(paragraphs.chunks == ["first\n\nsecond"], "under-budget paragraphs stay one request")
        expect(!paragraphs.wasTruncated, "under-budget text should not mark truncation")

        let lines = TextChunker.chunk(text: "first\nsecond", maxCharacters: 100, splitLongInput: true)
        expect(lines.chunks == ["first\nsecond"], "under-budget line breaks stay one request")

        let packed = TextChunker.chunk(text: "aaaa\n\nbbbb\n\ncccc", maxCharacters: 10, splitLongInput: true)
        expect(packed.chunks == ["aaaa\n\nbbbb", "cccc"], "over-budget paragraphs should pack by capacity")

        let long = TextChunker.chunk(text: "alpha beta gamma", maxCharacters: 10, splitLongInput: true)
        expect(long.chunks == ["alpha", "beta gamma"], "long text should split on whitespace")
    }

    private static func testAccessibilitySelectionHelpers() {
        expect(AccessibilitySelectionHelpers.preview("hello") == "hello", "short preview unchanged")
        expect(AccessibilitySelectionHelpers.preview("a\nb") == "a\\nb", "preview escapes newlines")
        expect(
            AccessibilitySelectionHelpers.preview(String(repeating: "x", count: 130), maxLength: 10) == "xxxxxxxxxx...",
            "preview truncates with ellipsis"
        )

        expect(AccessibilitySelectionHelpers.nonEmptyTrimmed("   ") == nil, "blank becomes nil")
        expect(AccessibilitySelectionHelpers.nonEmptyTrimmed("  hi  ") == "hi", "trim non-empty")

        expect(AccessibilitySelectionHelpers.substringUTF16("abcdef", location: 1, length: 3) == "bcd", "utf16 substring")
        expect(AccessibilitySelectionHelpers.substringUTF16("abc", location: 2, length: 5) == nil, "oob utf16 substring")

        expect(
            AccessibilitySelectionHelpers.sanitizeSelectedText("hello\r\n\r\n\r\nworld\u{200B}") == "hello\n\nworld",
            "sanitize line endings and zero-width"
        )
    }

    private static func testSelectionAutoPopupPolicy() {
        expect(
            SelectionAutoPopupPolicy.acceptsAXSelection(
                textLength: 5,
                hasAnchorRect: true,
                anchorNearMouse: true,
                allowMissingAnchor: false
            ),
            "anchored near-mouse selection should show bubble"
        )
        expect(
            SelectionAutoPopupPolicy.acceptsAXSelection(
                textLength: 5,
                hasAnchorRect: true,
                anchorNearMouse: false,
                allowMissingAnchor: true
            ),
            "intentional gesture should accept AX text even with far/wrong anchor (old clipboard path covered this)"
        )
        expect(
            !SelectionAutoPopupPolicy.acceptsAXSelection(
                textLength: 5,
                hasAnchorRect: true,
                anchorNearMouse: false,
                allowMissingAnchor: false
            ),
            "far anchor without intentional gesture must not show bubble"
        )
        expect(
            SelectionAutoPopupPolicy.acceptsAXSelection(
                textLength: 5,
                hasAnchorRect: false,
                anchorNearMouse: false,
                allowMissingAnchor: true
            ),
            "intentional drag/multi-click with AX text but no bounds should still show bubble"
        )
        expect(
            !SelectionAutoPopupPolicy.acceptsAXSelection(
                textLength: 5,
                hasAnchorRect: false,
                anchorNearMouse: false,
                allowMissingAnchor: false
            ),
            "missing anchor without intentional gesture must not show bubble"
        )
        expect(
            !SelectionAutoPopupPolicy.acceptsAXSelection(
                textLength: 1,
                hasAnchorRect: false,
                anchorNearMouse: false,
                allowMissingAnchor: true
            ),
            "single-character selection is ignored"
        )
    }

    private static func testSSEEventParser() {
        func parse(_ body: String) -> [SSEEvent] {
            var parser = SSEEventParser()
            var events: [SSEEvent] = []
            for byte in Array(body.utf8) {
                events.append(contentsOf: parser.append(byte: byte))
            }
            events.append(contentsOf: parser.finish())
            return events
        }

        let lf = parse("data: one\n\ndata: two\n\n")
        expect(lf.map(\.data) == ["one", "two"], "LF-delimited events")

        let crlf = parse("data: one\r\n\r\ndata: two\r\n\r\n")
        expect(crlf.map(\.data) == ["one", "two"], "CRLF-delimited events")

        let multiline = parse("event: delta\ndata: a\ndata: b\n\n")
        expect(multiline == [SSEEvent(event: "delta", data: "a\nb", id: nil)], "multi-line data joins with newline")

        let commentsAndBOM = parse("\u{FEFF}: keep-alive\ndata: x\n\n")
        expect(commentsAndBOM.map(\.data) == ["x"], "BOM and comment lines are skipped")

        let unterminated = parse("data: tail")
        expect(unterminated.map(\.data) == ["tail"], "finish() flushes an unterminated event")

        let utf8 = parse("data: 你好\n\n")
        expect(utf8.map(\.data) == ["你好"], "multi-byte UTF-8 survives byte-wise parsing")
    }

    private static func testLLMStreamEventParser() {
        func json(_ string: String) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(string.utf8))) as? [String: Any] ?? [:]
        }

        func chat(_ string: String) -> LLMStreamEvent? {
            try? LLMStreamEventParser.chatCompletionsEvent(from: json(string))
        }

        func responses(_ string: String) -> LLMStreamEvent? {
            try? LLMStreamEventParser.responsesEvent(from: json(string))
        }

        func chatError(_ string: String) -> String? {
            do {
                _ = try LLMStreamEventParser.chatCompletionsEvent(from: json(string))
                return nil
            } catch let error as LLMStreamProviderError {
                return error.message
            } catch {
                return nil
            }
        }

        func responsesError(_ string: String) -> String? {
            do {
                _ = try LLMStreamEventParser.responsesEvent(from: json(string))
                return nil
            } catch let error as LLMStreamProviderError {
                return error.message
            } catch {
                return nil
            }
        }

        expect(chat(#"{"choices":[{"delta":{"content":"hi"}}]}"#) == .text("hi"), "chat text delta")
        expect(chat(#"{"choices":[{"delta":{"content":"","reasoning_content":"hmm"}}]}"#) == .activity(.thinking), "chat reasoning delta")
        expect(chat(#"{"choices":[{"delta":{"role":"assistant"}}]}"#) == nil, "chat role-only delta")
        expect(chat(#"{"error":null,"choices":[{"delta":{"content":"ok"}}]}"#) == .text("ok"), "chat null error field is ignored")
        expect(chatError(#"{"error":{"message":"quota exceeded"}}"#) == "quota exceeded", "chat in-stream error")

        expect(responses(#"{"type":"response.output_text.delta","delta":"hi"}"#) == .text("hi"), "responses text delta")
        expect(responses(#"{"type":"response.output_text.annotation.added","annotation":{}}"#) == nil, "responses annotation is not text")
        expect(responses(#"{"type":"response.output_item.added","item":{"type":"reasoning"}}"#) == .activity(.thinking), "responses reasoning item")
        expect(responses(#"{"type":"response.output_item.added","item":{"type":"web_search_call"}}"#) == .activity(.searching), "responses search item")
        expect(responses(#"{"type":"response.web_search_call.searching"}"#) == .activity(.searching), "responses search progress")
        expect(responses(#"{"type":"response.completed"}"#) == nil, "responses completion")
        expect(responsesError(#"{"type":"error","message":"bad request"}"#) == "bad request", "responses error event")
        expect(
            responsesError(#"{"type":"response.failed","response":{"error":{"message":"server overloaded"}}}"#) == "server overloaded",
            "responses failed event"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Smoke test failed: \(message)")
        }
    }
}

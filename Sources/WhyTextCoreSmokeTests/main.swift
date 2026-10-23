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
        testTranslationDirection()
        testChunkAssembly()
        testRecentList()
        testSemanticVersion()
        testOCRTextLayout()
        try testReadingMemory()
        testSentenceContext()
        testGlossaryMatcher()
        testPanelPlacement()
        testMemoryMarkdownExporter()
        try testLocalization()
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

    private static func testTranslationDirection() {
        func target(_ text: String, _ primary: TranslationLanguage = .simplifiedChinese, _ secondary: TranslationLanguage = .english) -> TranslationLanguage {
            TranslationDirection.target(for: text, primary: primary, secondary: secondary)
        }

        expect(target("The quick brown fox jumps over the lazy dog.") == .simplifiedChinese, "English goes to primary")
        expect(target("今天天气很好，我们一起去公园散步吧。") == .english, "Chinese goes to secondary")
        expect(target("這是一段繁體中文的句子，用來測試。") == .english, "Traditional Chinese counts as primary Chinese")
        expect(target("这个 API 的返回值需要处理一下错误情况。") == .english, "Chinese with Latin terms stays Chinese")
        expect(target("今日はとても良い天気ですね。") == .simplifiedChinese, "Japanese goes to primary")
        expect(target("12345 !!!") == .simplifiedChinese, "no letters falls back to primary")
        expect(target("Bonjour tout le monde, comment allez-vous ?", .english, .french) == .english, "French goes to English primary")
        expect(target("Hello there, how are you doing today?", .english, .japanese) == .japanese, "English primary goes to secondary")
        expect(target("Hello there, how are you doing today?", .english, .english) == .english, "same languages stay primary")
    }

    private static func testChunkAssembly() {
        var assembly = ChunkAssembly(count: 3)
        expect(assembly.visibleText == "", "empty assembly shows nothing")

        assembly.finish("C", at: 2)
        expect(assembly.visibleText == "", "a later chunk stays hidden until earlier ones finish")

        assembly.setPartial("A1", at: 0)
        expect(assembly.visibleText == "A1", "first chunk streams")

        assembly.finish("A", at: 0)
        expect(assembly.visibleText == "A\n\n", "finished chunk opens the next slot")

        assembly.setPartial("B1", at: 1)
        expect(assembly.visibleText == "A\n\nB1", "second chunk streams after the first")
        expect(!assembly.isComplete, "not complete while a chunk runs")

        assembly.finish("B", at: 1)
        expect(assembly.visibleText == "A\n\nB\n\nC", "early-finished chunk appears in order")
        expect(assembly.isComplete && assembly.fullText == "A\n\nB\n\nC", "complete text joins all chunks")
    }

    private static func testRecentList() {
        var list = RecentList<Int>(capacity: 3)
        for value in [1, 2, 3] {
            list.insert(value, replacing: { $0 == value })
        }
        expect(list.items == [3, 2, 1], "most recent first")

        list.insert(1, replacing: { $0 == 1 })
        expect(list.items == [1, 3, 2], "re-inserting moves to front without duplicates")

        list.insert(4, replacing: { $0 == 4 })
        expect(list.items == [4, 1, 3], "capacity drops the oldest")

        let seeded = RecentList(items: [1, 2, 3, 4, 5], capacity: 2)
        expect(seeded.items == [1, 2], "seeded items are capped")
    }

    private static func testSemanticVersion() {
        func v(_ string: String) -> SemanticVersion? { SemanticVersion(string) }

        expect(v("v0.2.3")?.description == "0.2.3", "leading v is dropped")
        expect(v("0.2.10")! > v("0.2.9")!, "components compare numerically")
        expect(v("1.0")! == v("1.0.0")!, "missing components count as zero")
        expect(v("0.3.0")! > v("0.2.99")!, "minor beats patch")
        expect(!(v("0.2.3")! > v("0.2.3")!), "equal versions are not newer")
        expect(v("") == nil && v("1.x") == nil && v("1..2") == nil && v("1.0-beta") == nil, "malformed versions are rejected")
    }

    private static func testOCRTextLayout() {
        // Rows 0.05 tall; consecutive rows of a paragraph are 0.02 apart.
        func line(_ text: String, row: Double, minX: Double = 0.05, maxX: Double = 0.95) -> OCRTextLayout.Line {
            OCRTextLayout.Line(text: text, minX: minX, top: row * 0.07, maxX: maxX, bottom: row * 0.07 + 0.05)
        }

        expect(OCRTextLayout.join([]) == "", "no lines")

        let wrappedEnglish = OCRTextLayout.join([
            line("The quick brown fox jumps over", row: 0),
            line("the lazy dog and keeps run-", row: 1),
            line("ning into the woods.", row: 2),
        ])
        expect(wrappedEnglish == "The quick brown fox jumps over the lazy dog and keeps running into the woods.", "wrapped Latin lines join with spaces and rejoin hyphenated words")

        let wrappedChinese = OCRTextLayout.join([
            line("今天天气很好，我们一起去", row: 0),
            line("公园散步吧。", row: 1),
        ])
        expect(wrappedChinese == "今天天气很好，我们一起去公园散步吧。", "wrapped CJK lines join without spaces")

        let paragraphs = OCRTextLayout.join([
            line("First paragraph line one", row: 0),
            line("continues here.", row: 1),
            line("Second paragraph.", row: 3),
        ])
        expect(paragraphs == "First paragraph line one continues here.\n\nSecond paragraph.", "a blank-line gap starts a new paragraph")

        let heading = OCRTextLayout.join([
            line("Title", row: 0, maxX: 0.2),
            line("Body text that fills the whole width of the column", row: 1),
        ])
        expect(heading == "Title\nBody text that fills the whole width of the column", "a short line stays on its own line")

        let sameRow = OCRTextLayout.join([
            line("Value", row: 0, minX: 0.6, maxX: 0.9),
            line("Label:", row: 0, minX: 0.05, maxX: 0.3),
        ])
        expect(sameRow == "Label: Value", "pieces on one row join left to right")

        let unsorted = OCRTextLayout.join([
            line("second line of the same paragraph", row: 1),
            line("This is the first line, and", row: 0),
        ])
        expect(unsorted == "This is the first line, and second line of the same paragraph", "lines are ordered top to bottom")
    }

    private static func testReadingMemory() throws {
        expect(TermKey.make("  Moat. ") == "moat", "term key trims, lowercases, and drops punctuation")
        expect(TermKey.make("context\n  window") == "context window", "term key collapses whitespace")
        expect(TermKey.make("护城河") == "护城河", "CJK terms are kept")
        expect(TermKey.make(String(repeating: "a", count: 41)) == nil, "over 40 characters is a passage")
        expect(TermKey.make("one two three four five") == nil, "more than four words is a passage")
        expect(TermKey.make(" ... ") == nil, "punctuation alone is not a term")

        let record = LookupRecord(
            date: Date(timeIntervalSince1970: 1_761_000_000),
            sessionID: UUID(),
            action: "translate",
            input: .selection,
            sourceText: "Moat",
            resultText: "护城河",
            targetLanguage: "zh-Hans",
            source: LookupSource(appName: "Safari", documentURL: "https://example.com/a")
        )
        expect(record.termKey == "moat", "records derive their term key")

        var log = try LookupLog.encodeLine(record)
        log.append(Data("{\"broken\": tr\n".utf8))
        log.append(try LookupLog.encodeLine(record))
        let decoded = LookupLog.decode(log)
        expect(decoded.count == 2, "a corrupt line is skipped, not fatal")
        expect(decoded.first == record, "records round-trip through a log line")
    }

    private static func testSentenceContext() {
        func extract(_ text: String, _ selection: String, occurrence: Int = 0,
                     expected: String? = nil, maxLength: Int = 400) -> String? {
            var range = (text as NSString).range(of: selection)
            for _ in 0..<occurrence {
                let from = NSMaxRange(range)
                range = (text as NSString).range(of: selection, range: NSRange(location: from, length: (text as NSString).length - from))
            }
            return SentenceContext.extract(fullText: text, selectionUTF16: range, expectedSelection: expected, maxLength: maxLength)
        }

        let text = "First one here. It wipes out moats and the middle. Last one."
        expect(extract(text, "moats") == "It wipes out moats and the middle.", "returns the sentence holding the selection")
        expect(extract(text, "middle. Last") == "It wipes out moats and the middle. Last one.", "a selection across sentences joins them")
        expect(extract(text, "It wipes out moats and the middle.") == nil, "a whole-sentence selection adds nothing")
        expect(extract("Line one\nkeeps going. Next.", "keeps") == "Line one keeps going.", "hard-wrapped lines join into one sentence")
        expect(extract("A heading\n\nThe body starts here.", "body") == "The body starts here.", "a blank line still ends a paragraph")
        expect(extract("A heading\r\nThe body starts here.", "body") == "The body starts here.", "CRLF is a line pair, not a wrap")
        expect(extract("我们读书。护城河很宽，难以逾越。然后呢？", "护城河") == "护城河很宽，难以逾越。", "CJK sentences split on 。")
        expect(extract(text, "moats", expected: "castles") == nil, "a range that doesn't match the selected text is ignored")
        expect(extract(text, "moats", expected: " moats ") != nil, "the match ignores surrounding whitespace")
        expect(SentenceContext.extract(fullText: "short", selectionUTF16: NSRange(location: 2, length: 10)) == nil, "out-of-range selections are rejected")

        let long = "Start " + String(repeating: "word ", count: 100) + "TARGET " + String(repeating: "word ", count: 100) + "end."
        let cut = extract(long, "TARGET", maxLength: 60) ?? ""
        expect(cut.hasPrefix("…") && cut.hasSuffix("…") && cut.contains("TARGET"), "long sentences are cut around the selection")
        expect(cut.count <= 62, "a cut sentence stays within the cap plus ellipses")
        let nearStart = extract(long, "Start", maxLength: 60) ?? ""
        expect(!nearStart.hasPrefix("…") && nearStart.hasSuffix("…"), "a selection at the start keeps the start")

        let emoji = "Hi. " + String(repeating: "👍", count: 40) + " TARGET " + String(repeating: "👍", count: 40) + "."
        let emojiCut = extract(emoji, "TARGET", maxLength: 21) ?? ""
        expect(emojiCut.contains("TARGET") && !emojiCut.unicodeScalars.contains { $0.value == 0xFFFD }, "cuts never split an emoji")
        expect(extract("The cat sat. The cat ran.", "cat", occurrence: 1) == "The cat ran.", "the selection's own occurrence is used")
    }

    private static func testGlossaryMatcher() {
        func entry(_ term: String, _ rendering: String = "x", target: String = "zh-Hans") -> GlossaryEntry {
            GlossaryEntry(term: term, rendering: rendering, targetLanguage: target, createdAt: Date(timeIntervalSince1970: 0))
        }
        func terms(_ text: String, _ entries: [GlossaryEntry], limit: Int = 20) -> [String] {
            GlossaryMatcher.matches(in: text, entries: entries, targetLanguage: "zh-Hans", limit: limit).map(\.term)
        }

        expect(terms("Key learnings from the year", [entry("learning")]).isEmpty, "whole words only")
        expect(terms("Machine Learning is fun", [entry("learning"), entry("machine learning")]) == ["machine learning", "learning"],
               "case-insensitive, longest term first")
        expect(terms("a learning moat", [entry("moat", target: "ja")]).isEmpty, "other target languages don't match")
        expect(terms("护城河很宽", [entry("护城河")]) == ["护城河"], "CJK terms match inside running text")
        expect(terms("写 C++ 代码", [entry("C++")]) == ["C++"], "terms with regex symbols match literally")
        expect(terms("ABC++ is not it", [entry("C++")]).isEmpty, "symbol terms still respect the edge before a letter")
        expect(terms("one two three", [entry("one"), entry("two"), entry("three")], limit: 2).count == 2, "results are capped")
        expect(terms("the moat", [entry("moat", " ")]).isEmpty, "blank renderings are ignored")

        expect(GlossaryMatcher.hint(for: []) == nil, "no matches, no hint")
        expect(GlossaryMatcher.hint(for: [entry(" moat ", "护城河")]) == "下列术语按给定译法翻译，不要改用别的说法：\n- moat → 护城河",
               "hint lists term → rendering")

        expect(GlossaryEntry.suggestedRendering(from: "\n 护城河 \n（比喻竞争壁垒）") == "护城河", "suggested rendering is the first line")
        expect(GlossaryEntry.suggestedRendering(from: String(repeating: "长", count: 100)).count == 60, "suggested rendering is capped")
    }

    private static func testPanelPlacement() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // A selected word in the middle of the screen (AppKit coordinates).
        let word = CGRect(x: 400, y: 500, width: 60, height: 18)
        let below = PanelPlacement.make(anchor: word, visibleFrame: screen, preferredMaxHeight: 560)
        expect(below.growth == .down && below.fixedEdgeY == 492, "prefers below the selection, top edge just under it")
        let small = below.frame(for: CGSize(width: 300, height: 120))
        let tall = below.frame(for: CGSize(width: 300, height: 400))
        expect(small.maxY == 492 && tall.maxY == 492, "growing keeps the top edge fixed")
        expect(tall.maxY <= word.minY && small.minX == 400, "never covers the selection; starts at its left edge")
        expect(below.frame(for: CGSize(width: 300, height: 2000)).height == below.maxHeight, "height is capped by room on screen")

        let nearBottom = CGRect(x: 400, y: 100, width: 60, height: 18)
        let above = PanelPlacement.make(anchor: nearBottom, visibleFrame: screen, preferredMaxHeight: 560)
        expect(above.growth == .up && above.fixedEdgeY == 126, "flips above when below is cramped")
        let grown = above.frame(for: CGSize(width: 300, height: 300))
        expect(grown.minY == 126 && grown.minY >= nearBottom.maxY, "growing upward keeps the bottom edge fixed, clear of the text")

        let rightEdge = CGRect(x: 1400, y: 500, width: 30, height: 18)
        let clamped = PanelPlacement.make(anchor: rightEdge, visibleFrame: screen, preferredMaxHeight: 560)
            .frame(for: CGSize(width: 400, height: 100))
        expect(clamped.maxX == 1440, "slides left to stay on screen")

        let everything = CGRect(x: 0, y: 20, width: 1440, height: 860)
        let fallback = PanelPlacement.make(anchor: everything, visibleFrame: screen, preferredMaxHeight: 560)
        expect(fallback.growth == .down && fallback.fixedEdgeY == 892 && fallback.maxHeight == 560,
               "a screen-filling selection hangs the panel from the top")

        let dragged = below.moved(to: CGRect(x: 100, y: 300, width: 300, height: 120), preferredMaxHeight: 560)
        expect(dragged.frame(for: CGSize(width: 300, height: 200)) == CGRect(x: 100, y: 220, width: 300, height: 200),
               "after a drag, growth continues from the dragged position")

        let bubble = CGRect(x: 470, y: 495, width: 120, height: 28)
        let origin = below.origin(for: CGSize(width: 300, height: 120), emergingFrom: bubble)
        expect(origin == CGPoint(x: 470, y: 523 - 120), "emerging from the bubble lines up with its top-left")

        // AX: top-left origin on the primary screen.
        let screens = [screen, CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let ax = CGRect(x: 400, y: 382, width: 60, height: 18)
        expect(AXGeometry.cocoaRect(fromAX: ax, primaryScreenHeight: 900, screens: screens, near: CGPoint(x: 410, y: 510)) == word,
               "AX rects flip against the primary screen")
        let secondary = CGRect(x: 2000, y: 100, width: 40, height: 20)
        expect(AXGeometry.cocoaRect(fromAX: secondary, primaryScreenHeight: 900, screens: screens, near: CGPoint(x: 2010, y: 790))
               == CGRect(x: 2000, y: 780, width: 40, height: 20), "rects on a taller secondary screen flip against the primary")
        expect(AXGeometry.cocoaRect(fromAX: .zero, primaryScreenHeight: 900, screens: screens, near: .zero) == nil, "empty rects are ignored")
        expect(AXGeometry.cocoaRect(fromAX: CGRect(x: 9000, y: 9000, width: 10, height: 10), primaryScreenHeight: 900,
                                    screens: screens, near: .zero) == nil, "off-screen rects are ignored")
    }

    private static func testMemoryMarkdownExporter() {
        L10n.language = .simplifiedChinese
        let utc = TimeZone(identifier: "UTC")!
        let session = UUID()
        func lookup(_ text: String, _ result: String, at seconds: TimeInterval, session: UUID = UUID(),
                    action: String = "translate", source: LookupSource = LookupSource()) -> LookupRecord {
            LookupRecord(date: Date(timeIntervalSince1970: seconds), sessionID: session, action: action,
                         input: .selection, sourceText: text, resultText: result, targetLanguage: nil, source: source)
        }
        // 2025-10-20 22:40 UTC and later.
        let base: TimeInterval = 1_761_000_000
        let records = [
            lookup("Moat", "护城河", at: base, session: session, source: LookupSource(
                appName: "Safari", windowTitle: "Make Something Heavy",
                documentURL: "https://example.com/heavy",
                sentence: "It largely wipes out moats and the middle."
            )),
            lookup("moat", "护城河（壁垒）", at: base + 60, session: session, action: "explain"),
            lookup("MOAT", "护城河", at: base + 86_400 * 15, source: LookupSource(
                appName: "Preview", documentURL: "file:///Users/me/Zero%20to%20One.pdf"
            )),
            lookup("a/b:c", "斜杠", at: base + 120),
            lookup("A?B:C", "问号", at: base + 180),
            lookup("This is a long passage that is not a term at all.", "长段落", at: base + 240),
        ]
        let files = MemoryMarkdownExporter.render(records: records, exportedAt: Date(timeIntervalSince1970: base), timeZone: utc)

        expect(files[MemoryMarkdownExporter.markerFileName] == "", "export carries its marker file")
        expect(files["README.md"]?.contains("记录总数：6") == true, "readme counts records")
        expect(Set(files.keys.filter { $0.hasPrefix("词条/") }) == ["词条/MOAT.md", "词条/a b c.md", "词条/A B C (2).md"],
               "terms group by key, names are sanitized, and case-insensitive clashes get a suffix")

        let moat = files["词条/MOAT.md"] ?? ""
        expect(moat.contains("count: 2"), "count is panel sessions, not records")
        expect(moat.contains("first_seen: 2025-10-20") && moat.contains("last_seen: 2025-11-04"), "first and last seen dates")
        expect(moat.contains("**来源**：Make Something Heavy — https://example.com/heavy"), "title and web address")
        expect(moat.contains("**来源**：Zero to One.pdf"), "local documents show the file name only")
        expect(moat.contains("> It largely wipes out **moat**s and the middle."), "the looked-up text is bolded in its sentence")
        expect(moat.contains("## 2025-10-20 · 解释"), "records without an app omit it from the heading")
        expect(moat.range(of: "2025-11-04")!.lowerBound < moat.range(of: "## 2025-10-20")!.lowerBound, "newest first")

        expect(Set(files.keys.filter { $0.hasPrefix("日志/") }) == ["日志/2025-10.md", "日志/2025-11.md"], "one log per month")
        let october = files["日志/2025-10.md"] ?? ""
        expect(october.contains("> This is a long passage that is not a term at all."), "passages appear in the log")
        expect(october.range(of: "护城河（壁垒）")!.lowerBound > october.range(of: "### 10-20 22:40 · 翻译 · Safari")!.lowerBound,
               "the log is oldest first")

        expect(files["术语表.md"] == nil, "no glossary file without glossary entries")
        expect(moat.contains("in_glossary: false"), "terms not in the glossary say so")

        let glossary = [
            GlossaryEntry(term: "Moat", rendering: "护城河", targetLanguage: "zh-Hans", note: "a|b", createdAt: Date(timeIntervalSince1970: base)),
            GlossaryEntry(term: "api", rendering: "接口\n层", targetLanguage: "xx", createdAt: Date(timeIntervalSince1970: base)),
        ]
        let withGlossary = MemoryMarkdownExporter.render(records: records, glossary: glossary,
                                                         exportedAt: Date(timeIntervalSince1970: base), timeZone: utc)
        let table = withGlossary["术语表.md"] ?? ""
        expect(table.contains("| Moat | 护城河 | 简体中文 | a\\|b |"), "glossary rows name the language and escape pipes")
        expect(table.contains("| api | 接口 层 | xx |  |"), "line breaks become spaces; unknown languages show their code")
        expect(table.range(of: "| api")!.lowerBound < table.range(of: "| Moat")!.lowerBound, "glossary is sorted by term")
        expect(withGlossary["词条/MOAT.md"]?.contains("in_glossary: true") == true, "starred terms are marked by term key")

        expect(MemoryMarkdownExporter.fileName(for: "..hidden") == "hidden", "never a hidden file")
        expect(MemoryMarkdownExporter.fileName(for: "\n") == "untitled", "empty names get a fallback")
        expect(MemoryMarkdownExporter.fileName(for: String(repeating: "长", count: 100)).count == 80, "names are capped")
    }

    private static func testLocalization() throws {
        let match = { InterfaceLanguage.match(preferredLanguages: $0) }
        expect(match(["zh-Hans-CN"]) == .simplifiedChinese, "zh-Hans maps to Simplified Chinese")
        expect(match(["zh-Hant-TW"]) == .traditionalChinese && match(["zh-HK"]) == .traditionalChinese, "zh-Hant and zh-HK map to Traditional Chinese")
        expect(match(["fr-FR", "ja-JP"]) == .japanese, "first supported preferred language wins")
        expect(match(["fr-FR"]) == .english, "unsupported languages fall back to English")
        expect(InterfaceLanguage.korean.resolved() == .korean, "concrete languages resolve to themselves")

        let tables: [(InterfaceLanguage, [String: String])] = InterfaceLanguage.allCases.compactMap { language in
            guard language != .system, let table = L10n.table(for: language) else { return nil }
            return (language, table)
        }
        expect(tables.count == 4, "four translated tables")

        let placeholder = try NSRegularExpression(pattern: #"%(?:\d\$)?@|\{\{(?:text|target)\}\}"#)
        func tokens(_ string: String) -> [String] {
            placeholder.matches(in: string, range: NSRange(string.startIndex..., in: string))
                .map { (string as NSString).substring(with: $0.range) }
                .sorted()
        }

        // Every key the app uses must be translated everywhere. Read from the source
        // tree, so this runs from the package root (as `swift run` and CI do).
        let usedKeys = try localizationKeysInSources()
        expect(!usedKeys.isEmpty, "found localization keys in Sources/")
        for (language, table) in tables {
            for key in usedKeys {
                expect(table[key] != nil, "\(language.rawValue) is missing \"\(key)\"")
            }
            for (key, value) in table {
                expect(usedKeys.contains(key), "\(language.rawValue) has unused key \"\(key)\"")
                expect(tokens(key) == tokens(value), "\(language.rawValue) placeholders differ for \"\(key)\"")
            }
        }

        L10n.language = .english
        expect(L10n.t("翻译") == "Translate", "lookup uses the current language")
        expect(L10n.f("发现新版本 %@", "1.2.0") == "Version 1.2.0 is available", "arguments format")
        L10n.language = .simplifiedChinese
        expect(L10n.t("翻译") == "翻译", "Simplified Chinese returns the key")
        expect(L10n.t("not a key") == "not a key", "unknown keys fall back to themselves")
    }

    private static func localizationKeysInSources() throws -> Set<String> {
        let call = try NSRegularExpression(pattern: #"L10n\.[tf]\(\s*"((?:[^"\\]|\\.)*)""#)
        var keys = Set<String>()
        for directory in ["Sources/WhyText", "Sources/WhyTextCore"] {
            guard let files = FileManager.default.enumerator(atPath: directory) else { continue }
            for case let file as String in files where file.hasSuffix(".swift") {
                let source = try String(contentsOfFile: "\(directory)/\(file)", encoding: .utf8)
                for match in call.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                    keys.insert((source as NSString).substring(with: match.range(at: 1)))
                }
            }
        }
        return keys
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Smoke test failed: \(message)")
        }
    }
}

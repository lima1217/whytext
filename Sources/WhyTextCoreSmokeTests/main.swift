import Foundation
import WhyTextCore

@main
enum WhyTextCoreSmokeTests {
    static func main() throws {
        try testProviderEndpointBuilder()
        testCJKLatinSpacer()
        testTextChunker()
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
        expect(paragraphs.chunks == ["first", "second"], "paragraphs should split independently")
        expect(!paragraphs.wasTruncated, "paragraph splitting should not mark truncation")

        let lines = TextChunker.chunk(text: "first\nsecond", maxCharacters: 100, splitLongInput: true)
        expect(lines.chunks == ["first", "second"], "single-newline structured input should split independently")

        let long = TextChunker.chunk(text: "alpha beta gamma", maxCharacters: 10, splitLongInput: true)
        expect(long.chunks == ["alpha", "beta gamma"], "long text should split on whitespace")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Smoke test failed: \(message)")
        }
    }
}

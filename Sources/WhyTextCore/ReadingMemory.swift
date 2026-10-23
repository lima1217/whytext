import Foundation

/// How the text of a lookup reached WhyText.
public enum LookupInput: String, Codable, Sendable {
    case selection
    case bubble
    case manual
    case screenshot
}

/// Where the looked-up text was read. Every field is best-effort: apps expose
/// different parts of this through Accessibility, and some expose none.
public struct LookupSource: Codable, Equatable, Sendable {
    public var appName: String?
    public var bundleID: String?
    public var windowTitle: String?
    /// The web page (`http`/`https`) or document (`file`) the text came from.
    public var documentURL: String?
    /// The sentence around the selection, when the app exposes the full text.
    public var sentence: String?

    public init(
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil,
        documentURL: String? = nil,
        sentence: String? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.documentURL = documentURL
        self.sentence = sentence
    }
}

/// One finished translation or explanation, kept so reading leaves something behind.
public struct LookupRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    /// One panel opening. Switching translate/explain or the target language in the
    /// same panel records again under the same session, but counts as one lookup.
    public var sessionID: UUID
    /// `PanelAction.rawValue`: "translate" or "explain".
    public var action: String
    public var input: LookupInput
    public var sourceText: String
    public var resultText: String
    /// `TranslationLanguage.rawValue`; nil for explanations.
    public var targetLanguage: String?
    public var source: LookupSource
    /// Short selections only; groups repeat lookups of the same word or phrase.
    public var termKey: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        sessionID: UUID,
        action: String,
        input: LookupInput,
        sourceText: String,
        resultText: String,
        targetLanguage: String?,
        source: LookupSource
    ) {
        self.id = id
        self.date = date
        self.sessionID = sessionID
        self.action = action
        self.input = input
        self.sourceText = sourceText
        self.resultText = resultText
        self.targetLanguage = targetLanguage
        self.source = source
        self.termKey = TermKey.make(sourceText)
    }
}

/// Normalizes a short selection so repeat lookups of one word or phrase match.
public enum TermKey {
    public static let maxCharacters = 40
    public static let maxLatinWords = 4

    /// nil for passages: longer than 40 characters, or more than 4 words.
    public static func make(_ text: String) -> String? {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !collapsed.isEmpty, collapsed.count <= maxLatinWords else { return nil }

        let joined = collapsed.joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
            .lowercased()
        guard !joined.isEmpty, joined.count <= maxCharacters else { return nil }
        return joined
    }
}

/// `lookups.jsonl`: one JSON record per line, so a save only appends.
public enum LookupLog {
    public static func encodeLine(_ record: LookupRecord) throws -> Data {
        var data = try encoder.encode(record)
        data.append(0x0A)
        return data
    }

    /// Skips lines that don't decode, so a line cut short by a crash costs one record.
    public static func decode(_ data: Data) -> [LookupRecord] {
        data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(LookupRecord.self, from: Data(line))
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

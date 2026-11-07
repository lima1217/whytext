import Foundation

/// The language WhyText's own interface is shown in. Independent of the
/// translation languages, and switchable without relaunching.
public enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    public var id: String { rawValue }

    /// Each language names itself, so it can be found whatever the current UI language.
    public var displayName: String {
        switch self {
        case .system: L10n.t("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    /// `.system` mapped to a concrete language; other cases return themselves.
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> InterfaceLanguage {
        guard self == .system else { return self }
        return Self.match(preferredLanguages: preferredLanguages)
    }

    /// The first of the user's macOS languages that WhyText supports; English otherwise.
    public static func match(preferredLanguages: [String]) -> InterfaceLanguage {
        for identifier in preferredLanguages {
            let lowered = identifier.lowercased()
            if lowered.hasPrefix("zh") {
                // zh-Hant, zh-TW, zh-HK and zh-MO all read Traditional Chinese.
                let traditional = ["hant", "-tw", "-hk", "-mo"].contains { lowered.contains($0) }
                return traditional ? .traditionalChinese : .simplifiedChinese
            }
            if lowered.hasPrefix("en") { return .english }
            if lowered.hasPrefix("ja") { return .japanese }
            if lowered.hasPrefix("ko") { return .korean }
        }
        return .english
    }
}

/// Interface strings. The Simplified Chinese text is the key; other languages look it
/// up in their table and fall back to the key when an entry is missing.
public enum L10n {
    private static let lock = NSLock()
    private static var _language: InterfaceLanguage = InterfaceLanguage.system.resolved()

    /// Always a concrete language (never `.system`).
    public static var language: InterfaceLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _language
        }
        set {
            lock.lock()
            _language = newValue.resolved()
            lock.unlock()
        }
    }

    /// Layout testing only: stretches English text by about 40% and brackets it,
    /// so truncation and overlap show up before real translations do.
    nonisolated(unsafe) public static var pseudoLocalize = false

    public static func t(_ key: String) -> String {
        let text = lookup(key, in: language)
        return pseudoLocalize ? pseudo(text) : text
    }

    static func pseudo(_ text: String) -> String {
        let accented: [Character: Character] = ["a": "á", "e": "é", "i": "í", "o": "ö", "u": "ü", "A": "Å", "E": "É", "O": "Ö", "c": "ç", "n": "ñ"]
        var out = ""
        var inPlaceholder = false
        for ch in text {
            if ch == "%" { inPlaceholder = true }
            out.append(inPlaceholder ? ch : (accented[ch] ?? ch))
            if inPlaceholder, ch == "@" { inPlaceholder = false }
        }
        let padding = String(repeating: "~", count: max(2, text.count * 2 / 5))
        return "[" + out + padding + "]"
    }

    /// Formats a key containing `%@` / `%1$@` placeholders with string arguments.
    public static func f(_ key: String, _ arguments: String...) -> String {
        String(format: t(key), arguments: arguments)
    }

    static func lookup(_ key: String, in language: InterfaceLanguage) -> String {
        guard let table = table(for: language) else { return key }
        return table[key] ?? key
    }

    /// Nil for Simplified Chinese, whose strings are the keys themselves.
    public static func table(for language: InterfaceLanguage) -> [String: String]? {
        switch language {
        case .system: table(for: language.resolved())
        case .simplifiedChinese: nil
        case .traditionalChinese: traditionalChinese
        case .english: english
        case .japanese: japanese
        case .korean: korean
        }
    }
}

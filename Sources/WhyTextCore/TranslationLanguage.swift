import Foundation
import NaturalLanguage

/// A translation target the user can pick. `promptName` is what `{{target}}`
/// renders to; the default prompts are Chinese, so names are Chinese too.
public enum TranslationLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .russian: "Русский"
        }
    }

    public var promptName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁体中文"
        case .english: "英文"
        case .japanese: "日文"
        case .korean: "韩文"
        case .french: "法文"
        case .german: "德文"
        case .spanish: "西班牙文"
        case .russian: "俄文"
        }
    }

    /// Simplified and traditional Chinese count as one language when deciding direction:
    /// a zh-Hans reader selecting zh-Hant text still wants it in their second language.
    fileprivate var family: String {
        switch self {
        case .simplifiedChinese, .traditionalChinese: "zh"
        default: rawValue
        }
    }
}

public enum TranslationDirection {
    /// Text already in the primary language goes to the secondary one; everything else
    /// goes to the primary language.
    public static func target(
        for text: String,
        primary: TranslationLanguage,
        secondary: TranslationLanguage
    ) -> TranslationLanguage {
        guard primary != secondary, let detected = detectFamily(text) else {
            return primary
        }
        return detected == primary.family ? secondary : primary
    }

    /// Language family of `text` ("zh", "en", "ja", …), or nil when undecidable.
    public static func detectFamily(_ text: String) -> String? {
        let sample = String(text.prefix(2000))
        guard sample.contains(where: { $0.isLetter }) else { return nil }

        // Kana is unambiguous Japanese; kanji-only snippets would otherwise read as Chinese.
        var han = 0
        var kana = 0
        for scalar in sample.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF:
                kana += 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                han += 1
            default:
                break
            }
        }
        if kana > 0 && kana * 5 >= han {
            return "ja"
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage else { return nil }

        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return "zh"
        default:
            return language.rawValue
        }
    }
}

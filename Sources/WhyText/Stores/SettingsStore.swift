import Combine
import Foundation
import WhyTextCore

final class SettingsStore: ObservableObject {
    static let defaultTranslatePromptTemplate = "把下面的文字翻译成{{target}}。只输出译文。\n\n{{text}}"

    /// Earlier translate defaults, upgraded the same way as the explain ones.
    static let legacyTranslatePromptTemplates = [
        // Before automatic direction: always English → Simplified Chinese.
        "把下面的英文翻译成简体中文。只输出译文。\n\n{{text}}",
    ]
    static let defaultExplainPromptTemplate = """
        我在读下面这段文字，想弄懂它在说什么。请用白话把内容讲清楚。

        解释的对象是内容本身：作者在讲什么事、想表达什么观点、凭什么这么说。不讲语言本身：不逐词释义，不谈原文用词、语法，也不谈怎么翻译或为什么这样译。原文是外文时，直接用中文讲它的内容。

        忠于原文事实与语气；只写原文能支撑的内容。

        1. 先用一句话点出它在讲什么。
           完成标准：读者不看原文也能抓住主题。
        2. 再补上读懂它需要的关键点：提到的概念、人物或事件指什么，隐含了什么前提，前后怎么推进。
           完成标准：每一句都能回溯到原文；说不清的标成不确定，不当成事实。
        3. 到此为止。
           完成标准：没有延伸议论、背景科普、或「还可以这样理解」。

        \(UnifiedTranslationRequest.webSearchInstruction)

        简体中文；短句；能短则短。

        <text>
        {{text}}
        </text>
        """

    /// Earlier explain defaults. Saved copies upgrade to the current default once,
    /// while customized prompts stay put.
    static let legacyExplainPromptTemplates = [
        // Before server-side search.
        """
        用白话讲清下面文字的要义。

        要义：作者实际想表达的意思。忠于原文事实与语气；只写原文能支撑的内容。

        1. 先用一句话点出它在讲什么。
           完成标准：读者不看原文也能抓住主题。
        2. 再用通俗话补上理解所需的关键点（难词、专名、隐含前提、句子关系）。
           完成标准：每一句都能回溯到原文；说不清的标成不确定，不当成事实。
        3. 到此为止。
           完成标准：没有延伸议论、背景科普、或「还可以这样理解」。

        简体中文；短句；能短则短。

        {{text}}
        """,
        // With search, but "难词" steered foreign-language input into word
        // glosses and translation notes instead of explaining the content.
        """
        用白话讲清下面文字的要义。

        要义：作者实际想表达的意思。忠于原文事实与语气；只写原文能支撑的内容。

        1. 先用一句话点出它在讲什么。
           完成标准：读者不看原文也能抓住主题。
        2. 再用通俗话补上理解所需的关键点（难词、专名、隐含前提、句子关系）。
           完成标准：每一句都能回溯到原文；说不清的标成不确定，不当成事实。
        3. 到此为止。
           完成标准：没有延伸议论、背景科普、或「还可以这样理解」。

        拿不准的专名、术语或背景，先搜索，拿到更精确的上下文再解释；搜完仍存疑的，照旧标成不确定。

        简体中文；短句；能短则短。

        {{text}}
        """,
    ]

    @Published var providers: [LLMProvider]
    @Published var selectedProviderID: UUID?
    @Published var translatePromptTemplate: String
    @Published var explainPromptTemplate: String
    @Published var hotKeyShortcut: KeyboardShortcut?
    @Published var enableStreaming: Bool
    @Published var maxInputCharacters: Int
    @Published var splitLongInput: Bool
    @Published var autoPopupOnSelection: Bool
    @Published var translationFontSize: Double
    /// Translation target for text in any other language.
    @Published var primaryLanguage: TranslationLanguage
    /// Translation target for text already in the primary language.
    @Published var secondaryLanguage: TranslationLanguage

    private var cancellables = Set<AnyCancellable>()
    private var persistWorkItem: DispatchWorkItem?
    private let userDefaultsKey = "WhyText.Settings.v1"
    private let apiKeychainStore: APIKeychainStore

    private static let persistDebounceInterval: TimeInterval = 0.35

    private static func defaultDeepSeekProvider() -> LLMProvider {
        LLMProvider(
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-chat",
            apiMode: .chatCompletions
        )
    }

    var selectedProvider: LLMProvider? {
        guard let selectedProviderID else { return nil }
        return providers.first(where: { $0.id == selectedProviderID })
    }

    init(apiKeychainStore: APIKeychainStore = APIKeychainStore()) {
        self.apiKeychainStore = apiKeychainStore

        var didMigratePlaintextAPIKey = false

        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            self.providers = decoded.providers
            self.selectedProviderID = decoded.selectedProviderID
            self.translatePromptTemplate = decoded.translatePromptTemplate
            self.explainPromptTemplate = decoded.explainPromptTemplate
            self.hotKeyShortcut = decoded.hotKeyShortcut
            self.enableStreaming = decoded.enableStreaming
            self.maxInputCharacters = decoded.maxInputCharacters
            self.splitLongInput = decoded.splitLongInput
            self.autoPopupOnSelection = decoded.autoPopupOnSelection
            self.translationFontSize = decoded.translationFontSize
            self.primaryLanguage = decoded.primaryLanguage
            self.secondaryLanguage = decoded.secondaryLanguage

            if self.translatePromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.translatePromptTemplate = Self.defaultTranslatePromptTemplate
            }

            if self.explainPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.explainPromptTemplate = Self.defaultExplainPromptTemplate
            }

            let translate = self.translatePromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.legacyTranslatePromptTemplates.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == translate
            }) {
                self.translatePromptTemplate = Self.defaultTranslatePromptTemplate
                schedulePersist()
            }

            let explain = self.explainPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.legacyExplainPromptTemplates.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == explain
            }) {
                self.explainPromptTemplate = Self.defaultExplainPromptTemplate
                schedulePersist()
            }

            if self.providers.isEmpty {
                let provider = Self.defaultDeepSeekProvider()
                self.providers = [provider]
                self.selectedProviderID = provider.id
            }

            if let selectedProviderID,
               !self.providers.contains(where: { $0.id == selectedProviderID }) {
                self.selectedProviderID = self.providers.first?.id
            }

            if self.providers.count == 1 {
                var provider = self.providers[0]
                let isLegacyDefault = provider.name == "OpenAI"
                    && provider.baseURL == "https://api.openai.com"
                    && provider.model == "gpt-4o-mini"
                    && provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isLegacyDefault {
                    let replacement = Self.defaultDeepSeekProvider()
                    provider.name = replacement.name
                    provider.baseURL = replacement.baseURL
                    provider.model = replacement.model
                    provider.apiMode = replacement.apiMode
                    self.providers[0] = provider
                    self.selectedProviderID = provider.id
                }
            }

            didMigratePlaintextAPIKey = migratePlaintextAPIKeysIfNeeded()
        } else {
            let defaultProvider = Self.defaultDeepSeekProvider()
            self.providers = [defaultProvider]
            self.selectedProviderID = defaultProvider.id
            self.translatePromptTemplate = Self.defaultTranslatePromptTemplate
            self.explainPromptTemplate = Self.defaultExplainPromptTemplate
            self.hotKeyShortcut = KeyboardShortcut.defaultShortcut
            self.enableStreaming = true
            self.maxInputCharacters = 4000
            self.splitLongInput = true
            self.autoPopupOnSelection = true
            self.translationFontSize = 16
            self.primaryLanguage = .simplifiedChinese
            self.secondaryLanguage = .english
        }

        bindAutoSave()

        if didMigratePlaintextAPIKey {
            persist()
        }
    }

    func addProvider() {
        let provider = Self.defaultDeepSeekProvider()
        providers.append(provider)
        selectedProviderID = provider.id
    }

    func removeProviders(withIDs ids: Set<UUID>) {
        for id in ids {
            _ = apiKeychainStore.deleteAPIKey(for: id)
        }

        providers.removeAll { ids.contains($0.id) }
        if let selectedProviderID, !providers.contains(where: { $0.id == selectedProviderID }) {
            self.selectedProviderID = providers.first?.id
        }
    }

    func apiKey(for providerID: UUID) -> String {
        apiKeychainStore.apiKey(for: providerID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func saveAPIKey(_ value: String, for providerID: UUID) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearAPIKey(for: providerID)
            return
        }

        _ = apiKeychainStore.saveAPIKey(trimmed, for: providerID)
    }

    func clearAPIKey(for providerID: UUID) {
        _ = apiKeychainStore.deleteAPIKey(for: providerID)
    }

    func resetTranslatePromptTemplateToDefault() {
        translatePromptTemplate = Self.defaultTranslatePromptTemplate
    }

    func resetExplainPromptTemplateToDefault() {
        explainPromptTemplate = Self.defaultExplainPromptTemplate
    }

    private func bindAutoSave() {
        $providers
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $selectedProviderID
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $translatePromptTemplate
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $explainPromptTemplate
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $hotKeyShortcut
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $enableStreaming
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $maxInputCharacters
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $splitLongInput
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $autoPopupOnSelection
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $translationFontSize
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $primaryLanguage
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)

        $secondaryLanguage
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePersist() }
            .store(in: &cancellables)
    }

    private func schedulePersist() {
        persistWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.persist()
        }

        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.persistDebounceInterval, execute: workItem)
    }

    private func persist() {
        let settings = PersistedSettings(
            providers: providers,
            selectedProviderID: selectedProviderID,
            translatePromptTemplate: translatePromptTemplate,
            explainPromptTemplate: explainPromptTemplate,
            hotKeyShortcut: hotKeyShortcut,
            enableStreaming: enableStreaming,
            maxInputCharacters: maxInputCharacters,
            splitLongInput: splitLongInput,
            autoPopupOnSelection: autoPopupOnSelection,
            translationFontSize: translationFontSize,
            primaryLanguage: primaryLanguage,
            secondaryLanguage: secondaryLanguage
        )
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func migratePlaintextAPIKeysIfNeeded() -> Bool {
        var migrated = false

        for idx in providers.indices {
            let key = providers[idx].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }

            _ = apiKeychainStore.saveAPIKey(key, for: providers[idx].id)
            providers[idx].apiKey = ""
            migrated = true
        }

        return migrated
    }

    deinit {
        persistWorkItem?.cancel()
        persist()
    }
}

private struct PersistedSettings: Codable {
    var providers: [LLMProvider]
    var selectedProviderID: UUID?
    var translatePromptTemplate: String
    var explainPromptTemplate: String
    var hotKeyShortcut: KeyboardShortcut?
    var enableStreaming: Bool
    var maxInputCharacters: Int
    var splitLongInput: Bool
    var autoPopupOnSelection: Bool
    var translationFontSize: Double
    var primaryLanguage: TranslationLanguage
    var secondaryLanguage: TranslationLanguage

    init(
        providers: [LLMProvider],
        selectedProviderID: UUID?,
        translatePromptTemplate: String,
        explainPromptTemplate: String,
        hotKeyShortcut: KeyboardShortcut?,
        enableStreaming: Bool,
        maxInputCharacters: Int,
        splitLongInput: Bool,
        autoPopupOnSelection: Bool,
        translationFontSize: Double,
        primaryLanguage: TranslationLanguage,
        secondaryLanguage: TranslationLanguage
    ) {
        self.providers = providers
        self.selectedProviderID = selectedProviderID
        self.translatePromptTemplate = translatePromptTemplate
        self.explainPromptTemplate = explainPromptTemplate
        self.hotKeyShortcut = hotKeyShortcut
        self.enableStreaming = enableStreaming
        self.maxInputCharacters = maxInputCharacters
        self.splitLongInput = splitLongInput
        self.autoPopupOnSelection = autoPopupOnSelection
        self.translationFontSize = translationFontSize
        self.primaryLanguage = primaryLanguage
        self.secondaryLanguage = secondaryLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providers = try container.decode([LLMProvider].self, forKey: .providers)
        self.selectedProviderID = try container.decodeIfPresent(UUID.self, forKey: .selectedProviderID)
        self.translatePromptTemplate = try container.decode(String.self, forKey: .translatePromptTemplate)
        self.explainPromptTemplate = try container.decodeIfPresent(String.self, forKey: .explainPromptTemplate)
            ?? SettingsStore.defaultExplainPromptTemplate
        self.hotKeyShortcut = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .hotKeyShortcut)
        self.enableStreaming = try container.decodeIfPresent(Bool.self, forKey: .enableStreaming) ?? true
        self.maxInputCharacters = try container.decodeIfPresent(Int.self, forKey: .maxInputCharacters) ?? 4000
        self.splitLongInput = try container.decodeIfPresent(Bool.self, forKey: .splitLongInput) ?? true
        self.autoPopupOnSelection = try container.decodeIfPresent(Bool.self, forKey: .autoPopupOnSelection) ?? true
        self.translationFontSize = try container.decodeIfPresent(Double.self, forKey: .translationFontSize) ?? 16
        // Unknown codes (e.g. from a newer build) fall back rather than wiping all settings.
        self.primaryLanguage = (try? container.decodeIfPresent(TranslationLanguage.self, forKey: .primaryLanguage)) ?? .simplifiedChinese
        self.secondaryLanguage = (try? container.decodeIfPresent(TranslationLanguage.self, forKey: .secondaryLanguage)) ?? .english
    }
}

struct LLMProvider: Identifiable, Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case model
        case apiMode
        case apiKey
    }

    var id: UUID
    var name: String
    var baseURL: String
    var model: String
    var apiMode: LLMAPIMode
    var apiKey: String

    init(id: UUID = UUID(), name: String, baseURL: String, model: String, apiMode: LLMAPIMode, apiKey: String = "") {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiMode = apiMode
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.model = try container.decode(String.self, forKey: .model)
        self.apiMode = try container.decode(LLMAPIMode.self, forKey: .apiMode)
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(apiMode, forKey: .apiMode)
    }
}

enum LLMAPIMode: String, Codable, CaseIterable, Identifiable {
    case chatCompletions
    case responses

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatCompletions:
            "Chat Completions (/v1/chat/completions)"
        case .responses:
            "Responses (/v1/responses)"
        }
    }
}

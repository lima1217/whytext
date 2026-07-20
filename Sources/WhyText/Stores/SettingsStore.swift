import Combine
import Foundation
import WhyTextCore

final class SettingsStore: ObservableObject {
    static let defaultTranslatePromptTemplate = "把下面的英文翻译成简体中文。只输出译文。\n\n{{text}}"
    static let defaultExplainPromptTemplate = """
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
        """

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

            if self.translatePromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.translatePromptTemplate = Self.defaultTranslatePromptTemplate
            }

            if self.explainPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.explainPromptTemplate = Self.defaultExplainPromptTemplate
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
        if let idx = providers.firstIndex(where: { $0.id == providerID }) {
            let cached = providers[idx].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cached.isEmpty {
                return cached
            }
        }

        let key = apiKeychainStore.apiKey(for: providerID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !key.isEmpty,
           let idx = providers.firstIndex(where: { $0.id == providerID }),
           providers[idx].apiKey != key {
            providers[idx].apiKey = key
        }

        return key
    }

    func saveAPIKey(_ value: String, for providerID: UUID) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearAPIKey(for: providerID)
            return
        }

        _ = apiKeychainStore.saveAPIKey(trimmed, for: providerID)

        if let idx = providers.firstIndex(where: { $0.id == providerID }) {
            providers[idx].apiKey = trimmed
        }
    }

    func clearAPIKey(for providerID: UUID) {
        _ = apiKeychainStore.deleteAPIKey(for: providerID)

        if let idx = providers.firstIndex(where: { $0.id == providerID }), !providers[idx].apiKey.isEmpty {
            providers[idx].apiKey = ""
        }
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
            translationFontSize: translationFontSize
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
        translationFontSize: Double
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

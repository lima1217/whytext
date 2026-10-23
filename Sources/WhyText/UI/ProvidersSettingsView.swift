import AppKit
import SwiftUI
import WhyTextCore

struct ProvidersSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showAddTemplate = false

    var body: some View {
        SettingsPage(.providers) {
            providerHeader
            if let index = selectedIndex {
                let providerID = appModel.settingsStore.providers[index].id
                ProviderDetailView(
                    provider: $appModel.settingsStore.providers[index],
                    loadAPIKey: {
                        appModel.settingsStore.apiKey(for: providerID)
                    },
                    saveAPIKey: { value in
                        appModel.settingsStore.saveAPIKey(value, for: providerID)
                    },
                    clearAPIKey: {
                        appModel.settingsStore.clearAPIKey(for: providerID)
                    },
                    testConnectivity: { provider, apiKey in
                        await appModel.testProviderConnectivity(provider: provider, apiKey: apiKey)
                    }
                )
                .id(providerID)
            } else {
                emptyState
            }
        }
        .onAppear { normalizeSelectionIfNeeded() }
    }

    // MARK: - Provider List Bar

    private var providerHeader: some View {
        Section {
            LabeledContent(L10n.t("服务商")) {
                HStack(spacing: Spacing.x2) {
                    if !appModel.settingsStore.providers.isEmpty {
                        Picker(L10n.t("服务商"), selection: providerSelectionBinding) {
                            ForEach(appModel.settingsStore.providers) { provider in
                                Text(provider.name.isEmpty ? L10n.t("未命名") : provider.name)
                                    .tag(Optional(provider.id))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    Button {
                        showAddTemplate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.t("添加服务商"))
                    .accessibilityLabel(L10n.t("添加服务商"))
                    .popover(isPresented: $showAddTemplate, arrowEdge: .bottom) {
                        addTemplatePopover
                    }

                    if appModel.settingsStore.providers.count > 1, let id = appModel.settingsStore.selectedProviderID {
                        Button {
                            appModel.settingsStore.removeProviders(withIDs: [id])
                        } label: {
                            Image(systemName: "minus")
                        }
                        .help(L10n.t("移除当前服务商"))
                        .accessibilityLabel(L10n.t("移除当前服务商"))
                    }
                }
            }
        }
    }

    // MARK: - Add Template Popover

    private var addTemplatePopover: some View {
        VStack(alignment: .leading, spacing: Spacing.x1) {
            ForEach(ProviderTemplate.allCases) { template in
                Button {
                    addProvider(from: template)
                    showAddTemplate = false
                } label: {
                    HStack(spacing: Spacing.x2_5) {
                        Image(systemName: template.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(AstryxColor.textSecondary)
                            .frame(width: 18)
                        Text(template.name)
                            .font(AstryxFont.bodyMedium)
                            .foregroundStyle(AstryxColor.textPrimary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.x2)
                    .padding(.vertical, Spacing.x1_5)
                    .contentShape(Rectangle())
                    .quietButtonHover(cornerRadius: Radius.inner)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.x1_5)
        .frame(width: 200)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Section {
            VStack(spacing: Spacing.x3) {
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AstryxColor.borderEmphasized)
                    .accessibilityHidden(true)
                Text(L10n.t("还没有服务商"))
                    .font(AstryxFont.bodySemibold)
                Button(L10n.t("添加服务商")) {
                    showAddTemplate = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.x4)
        }
    }

    // MARK: - Helpers

    private var providerSelectionBinding: Binding<UUID?> {
        Binding(
            get: { appModel.settingsStore.selectedProviderID },
            set: { appModel.settingsStore.selectedProviderID = $0 }
        )
    }

    private var selectedIndex: Int? {
        let providers = appModel.settingsStore.providers
        guard !providers.isEmpty else { return nil }
        if let id = appModel.settingsStore.selectedProviderID,
           let idx = providers.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return providers.indices.first
    }

    private func normalizeSelectionIfNeeded() {
        if let index = selectedIndex {
            appModel.settingsStore.selectedProviderID = appModel.settingsStore.providers[index].id
        }
    }

    private func addProvider(from template: ProviderTemplate) {
        let provider = template.makeProvider()
        appModel.settingsStore.providers.append(provider)
        appModel.settingsStore.selectedProviderID = provider.id
    }
}

// MARK: - Provider Templates

private enum ProviderTemplate: String, CaseIterable, Identifiable {
    case deepSeek
    case openAI
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .custom: L10n.t("自定义")
        }
    }


    var icon: String {
        switch self {
        case .deepSeek: "sparkles"
        case .openAI: "brain.head.profile"
        case .custom: "wrench.and.screwdriver"
        }
    }

    func makeProvider() -> LLMProvider {
        switch self {
        case .deepSeek:
            LLMProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "deepseek-chat", apiMode: .chatCompletions)
        case .openAI:
            LLMProvider(name: "OpenAI", baseURL: "https://api.openai.com", model: "gpt-4o-mini", apiMode: .chatCompletions)
        case .custom:
            LLMProvider(name: "Custom", baseURL: "", model: "", apiMode: .chatCompletions)
        }
    }
}

// MARK: - Provider Detail

private struct ProviderDetailView: View {
    @Binding var provider: LLMProvider
    let loadAPIKey: () -> String
    let saveAPIKey: (String) -> Void
    let clearAPIKey: () -> Void
    let testConnectivity: (LLMProvider, String) async -> ProviderConnectivityReport

    @State private var apiKeyDraft: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isTestingConnectivity = false
    @State private var connectivityReport: ProviderConnectivityReport?
    @State private var keychainRepairMessage: String?
    @State private var autoSaveTask: Task<Void, Never>?

    var body: some View {
        Group {
            Section {
                labeledField(title: L10n.t("名称"), placeholder: "My Provider", text: $provider.name)
                labeledField(title: "Base URL", placeholder: "https://api.deepseek.com", text: $provider.baseURL, monospaced: true)
                labeledField(title: "Model", placeholder: "deepseek-chat", text: $provider.model, monospaced: true)

                Picker(L10n.t("API 格式"), selection: $provider.apiMode) {
                    ForEach(LLMAPIMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section {
                LabeledContent("API Key") {
                    HStack(spacing: Spacing.x1_5) {
                        Group {
                            if showAPIKey {
                                TextField("", text: $apiKeyDraft, prompt: Text("sk-..."))
                            } else {
                                SecureField("", text: $apiKeyDraft, prompt: Text("sk-..."))
                            }
                        }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            ContextualIconSwap(
                                isActive: showAPIKey,
                                activeSystemName: "eye.slash",
                                inactiveSystemName: "eye",
                                size: 12
                            )
                            .foregroundStyle(AstryxColor.textSecondary)
                            .frame(width: 24, height: 24)
                            .quietButtonHover(cornerRadius: Radius.inner)
                        }
                        .buttonStyle(.quietIcon)
                        .help(showAPIKey ? L10n.t("隐藏 API Key") : L10n.t("显示 API Key"))
                        .accessibilityLabel(showAPIKey ? L10n.t("隐藏 API Key") : L10n.t("显示 API Key"))
                    }
                }

                // One row when it fits; otherwise the status takes its own line so no
                // button label truncates (long Japanese/English labels at minimum width).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.x2) {
                        apiKeyStatus
                        Spacer()
                        apiKeyActions
                    }
                    VStack(alignment: .leading, spacing: Spacing.x2) {
                        apiKeyStatus
                        HStack(spacing: Spacing.x2) {
                            Spacer()
                            apiKeyActions
                        }
                    }
                }

                if let report = connectivityReport {
                    statusRow(title: "Base URL", state: report.baseURL)
                    statusRow(title: "API Key", state: report.apiKey)
                    statusRow(title: "Model", state: report.model)

                    if !report.message.isEmpty {
                        Text(report.message)
                            .font(AstryxFont.captionM)
                            .foregroundStyle(AstryxColor.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear {
            apiKeyDraft = loadAPIKey()
            connectivityReport = nil
            keychainRepairMessage = nil
        }
        .onChange(of: apiKeyDraft) { newValue in
            connectivityReport = nil
            keychainRepairMessage = nil
            // Auto-save with debounce
            autoSaveTask?.cancel()
            autoSaveTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s debounce
                guard !Task.isCancelled else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    clearAPIKey()
                } else {
                    saveAPIKey(trimmed)
                }
            }
        }
        .onChange(of: provider.baseURL) { _ in connectivityReport = nil }
        .onChange(of: provider.model) { _ in connectivityReport = nil }
        .onChange(of: provider.apiMode) { _ in connectivityReport = nil }
        .onDisappear {
            autoSaveTask?.cancel()
            // Final save on disappear
            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                clearAPIKey()
            } else {
                saveAPIKey(trimmed)
            }
        }
    }

    // MARK: - API Key row

    private var apiKeyStatus: some View {
        HStack(spacing: Spacing.x2) {
            StatusBadge(
                text: apiKeyIsEmpty ? L10n.t("未填写") : L10n.t("已保存到 Keychain"),
                tone: apiKeyIsEmpty ? .warning : .success
            )

            if let keychainRepairMessage, !keychainRepairMessage.isEmpty {
                CaptionText(text: keychainRepairMessage)
            }
        }
    }

    @ViewBuilder
    private var apiKeyActions: some View {
        Button(L10n.t("粘贴")) {
            apiKeyDraft = NSPasteboard.general.string(forType: .string) ?? ""
        }
        .accessibilityLabel(L10n.t("粘贴 API Key"))

        Button(L10n.t("修复钥匙串")) {
            repairKeychainEntry()
        }
        .help(L10n.t("重新写入当前 API Key 到钥匙串"))

        Button(L10n.t("清除")) {
            apiKeyDraft = ""
        }
        .accessibilityLabel(L10n.t("清除 API Key"))

        if isTestingConnectivity {
            ProgressView()
                .controlSize(.small)
        }
        Button(isTestingConnectivity ? L10n.t("测试中…") : L10n.t("测试连通性")) {
            runConnectivityTest()
        }
        .disabled(isTestingConnectivity)
    }

    // MARK: - Helpers

    private func labeledField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        monospaced: Bool = false
    ) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(placeholder))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
    }

    private func repairKeychainEntry() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            keychainRepairMessage = L10n.t("请先填写 API Key，再执行修复。")
            return
        }

        saveAPIKey(trimmed)
        keychainRepairMessage = L10n.t("已重新保存到钥匙串。")
    }

    private func runConnectivityTest() {
        guard !isTestingConnectivity else { return }
        isTestingConnectivity = true
        let snapshot = provider
        let key = apiKeyDraft
        Task {
            let report = await testConnectivity(snapshot, key)
            await MainActor.run {
                self.connectivityReport = report
                self.isTestingConnectivity = false
            }
        }
    }

    private func statusRow(title: String, state: ConnectivityCheckState) -> some View {
        let tone = statusTone(for: state)
        return LabeledContent(title) {
            Label(state.label, systemImage: tone.icon)
                .foregroundStyle(tone.color)
        }
    }

    private var apiKeyIsEmpty: Bool {
        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func statusTone(for state: ConnectivityCheckState) -> Tone {
        switch state {
        case .available: .success
        case .unavailable: .danger
        case .unknown: .neutral
        }
    }
}

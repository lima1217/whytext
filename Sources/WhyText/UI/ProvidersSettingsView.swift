import AppKit
import SwiftUI

struct ProvidersSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showAddTemplate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                providerListBar
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
            .frame(maxWidth: 620)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .onAppear { normalizeSelectionIfNeeded() }
    }

    // MARK: - Provider List Bar

    private var providerListBar: some View {
        HStack(spacing: 8) {
            // Provider tabs
            ForEach(appModel.settingsStore.providers) { provider in
                let isActive = provider.id == appModel.settingsStore.selectedProviderID
                Button {
                    appModel.settingsStore.selectedProviderID = provider.id
                } label: {
                    Text(provider.name.isEmpty ? "未命名" : provider.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Add
            Button {
                showAddTemplate = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAddTemplate) {
                addTemplatePopover
            }

            // Remove (only if more than 1)
            if appModel.settingsStore.providers.count > 1, let id = appModel.settingsStore.selectedProviderID {
                Button {
                    appModel.settingsStore.removeProviders(withIDs: [id])
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Add Template Popover

    private var addTemplatePopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("添加 Provider")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            ForEach(ProviderTemplate.allCases) { template in
                Button {
                    addProvider(from: template)
                    showAddTemplate = false
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(template.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 220)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "network")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("无可用 Provider")
                .font(.headline)
            Button("添加一个") {
                showAddTemplate = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

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
        case .custom: "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .deepSeek: "api.deepseek.com"
        case .openAI: "api.openai.com"
        case .custom: "填写自定义接口"
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
    @State private var autoSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Provider fields
            GroupBox("接口") {
                VStack(alignment: .leading, spacing: 12) {
                    labeledField(title: "名称", placeholder: "My Provider", text: $provider.name)
                    labeledField(title: "Base URL", placeholder: "https://api.deepseek.com", text: $provider.baseURL, monospaced: true)
                    labeledField(title: "Model", placeholder: "deepseek-chat", text: $provider.model, monospaced: true)

                    HStack(spacing: 10) {
                        Text("API 格式")
                            .frame(width: 86, alignment: .leading)
                        Picker("", selection: $provider.apiMode) {
                            ForEach(LLMAPIMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            // API Key — auto-saves as you type
            GroupBox("API Key") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if showAPIKey {
                            TextField("sk-...", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showAPIKey ? "隐藏" : "显示")
                    }

                    HStack(spacing: 10) {
                        Text("自动保存到 Keychain")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Button("粘贴") {
                            apiKeyDraft = NSPasteboard.general.string(forType: .string) ?? ""
                        }

                        Button("清除") {
                            apiKeyDraft = ""
                        }
                    }
                }
                .padding(.top, 4)
            }

            // Connectivity test
            GroupBox("连通性") {
                VStack(alignment: .leading, spacing: 10) {
                    Button(isTestingConnectivity ? "测试中…" : "测试连通性") {
                        runConnectivityTest()
                    }
                    .disabled(isTestingConnectivity)

                    if let report = connectivityReport {
                        VStack(alignment: .leading, spacing: 4) {
                            statusRow(title: "Base URL", state: report.baseURL)
                            statusRow(title: "API Key", state: report.apiKey)
                            statusRow(title: "Model", state: report.model)
                        }

                        if !report.message.isEmpty {
                            Text(report.message)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            apiKeyDraft = loadAPIKey()
            connectivityReport = nil
        }
        .onChange(of: apiKeyDraft) { newValue in
            connectivityReport = nil
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

    // MARK: - Helpers

    private func labeledField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 86, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
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
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 70, alignment: .leading)
            Image(systemName: state.systemImage)
                .foregroundStyle(statusColor(for: state))
            Text(state.label)
                .foregroundStyle(statusColor(for: state))
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func statusColor(for state: ConnectivityCheckState) -> Color {
        switch state {
        case .available: .green
        case .unavailable: .red
        case .unknown: .secondary
        }
    }
}

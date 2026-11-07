import AppKit
import SwiftUI
import WhyTextCore

struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var selection: SettingsPane
    @State private var launchAtLoginState = LaunchAtLogin.state
    @State private var launchAtLoginError: String?

    var body: some View {
        SettingsPage(.general) {
            overviewSection
            interfaceLanguageSection
            startupSection
            historySection
        }
        // The user can flip login items in System Settings while we're open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginState = LaunchAtLogin.state
        }
    }

    // MARK: - Getting started

    /// The three things a lookup needs, in the order a new user should do them.
    /// Once all are ready, the section turns into a one-line reminder of how to use it.
    private var overviewSection: some View {
        let accessibilityReady = appModel.accessibilityStatus() == .trusted
        let providerReady = appModel.hasUsableProvider
        let shortcut = appModel.settingsStore.hotKeyShortcut
        let hotKeyReady = shortcut != nil && appModel.hotKeyIssue == nil
        let hotKeyText: String = {
            if let issue = appModel.hotKeyIssue { return issue.isBlocking ? L10n.t("快捷键不可用") : L10n.t("快捷键可能冲突") }
            return shortcut?.displayString ?? L10n.t("未设置快捷键")
        }()

        return Section {
            overviewRow(.permissions,
                        text: accessibilityReady ? L10n.t("已授权") : L10n.t("需要授权"),
                        ready: accessibilityReady)
            overviewRow(.providers,
                        text: providerReady ? (appModel.settingsStore.selectedProvider?.name ?? "") : L10n.t("需要 API Key"),
                        ready: providerReady)
            overviewRow(.shortcuts, text: hotKeyText, ready: hotKeyReady)
        } footer: {
            if accessibilityReady && providerReady, let shortcut, hotKeyReady {
                Text(L10n.f("在任意应用里选中文字，按 %@ 翻译。", shortcut.displayString))
                    .font(AstryxFont.captionM)
                    .foregroundStyle(AstryxColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func overviewRow(_ pane: SettingsPane, text: String, ready: Bool) -> some View {
        Button {
            selection = pane
        } label: {
            HStack(spacing: Spacing.x2_5) {
                PaneIcon(pane: pane, size: 20)
                Text(pane.title)
                    .foregroundStyle(AstryxColor.textPrimary)
                Spacer()
                SetupStatus(text: text, ready: ready)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AstryxColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Interface language

    private var interfaceLanguageSection: some View {
        Section {
            Picker(L10n.t("界面语言"), selection: $appModel.settingsStore.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section {
            Toggle(L10n.t("登录时自动启动"), isOn: launchAtLoginBinding)
            .toggleStyle(.switch)
            .disabled(launchAtLoginState == .unavailable)

            switch launchAtLoginState {
            case .requiresApproval:
                HStack(spacing: Spacing.x2) {
                    CaptionText(text: L10n.t("已在系统设置的「登录项」里被关闭，需要在那里重新允许。"))
                    Spacer()
                    Button(L10n.t("打开登录项设置")) {
                        LaunchAtLogin.openSystemSettings()
                    }
                }
            case .unavailable:
                CaptionText(text: L10n.t("把 WhyText 移到「应用程序」文件夹后可用。"))
            case .enabled, .disabled:
                EmptyView()
            }

            if let launchAtLoginError {
                CaptionText(text: launchAtLoginError)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginState == .enabled || launchAtLoginState == .requiresApproval },
            set: { enabled in
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = L10n.f("设置失败：%@", error.localizedDescription)
                }
                launchAtLoginState = LaunchAtLogin.state
            }
        )
    }

    // MARK: - History

    private var historySection: some View {
        Section {
            Toggle(isOn: $appModel.settingsStore.saveHistory) {
                SettingsRowLabel(
                    L10n.t("保存最近的翻译和解释"),
                    subtitle: L10n.t("可以在菜单栏的「最近」里重新打开。")
                )
            }
            .toggleStyle(.switch)

            if !appModel.historyStore.entries.isEmpty {
                LabeledContent(L10n.f("已保存 %@ 条", appModel.historyStore.entries.count.formatted())) {
                    Button(L10n.t("清除记录")) {
                        appModel.clearHistory()
                    }
                }
            }
        }
    }
}

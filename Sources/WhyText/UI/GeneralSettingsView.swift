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

    // MARK: - Overview

    private var overviewSection: some View {
        let accessibilityReady = appModel.accessibilityStatus() == .trusted
        let hotKeyReady = appModel.settingsStore.hotKeyShortcut != nil && appModel.hotKeyIssue == nil
        let hotKeyBlocked = appModel.hotKeyIssue?.isBlocking == true
        let hotKeyText = hotKeyReady
            ? L10n.t("快捷键已设置")
            : appModel.hotKeyIssue == nil
                ? L10n.t("未设置快捷键")
                : (hotKeyBlocked ? L10n.t("快捷键不可用") : L10n.t("快捷键可能冲突"))

        return Section {
            overviewRow(.shortcuts, text: hotKeyText, ready: hotKeyReady)
            overviewRow(
                .permissions,
                text: accessibilityReady ? L10n.t("辅助功能已授权") : L10n.t("需要辅助功能权限"),
                ready: accessibilityReady
            )
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
                StatusBadge(text: text, tone: ready ? .success : .warning)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AstryxColor.textDisabled)
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
                CaptionText(text: L10n.t("仅在打包后的 WhyText.app 中可用。"))
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
            Toggle(L10n.t("保存最近的翻译和解释"), isOn: $appModel.settingsStore.saveHistory)
                .toggleStyle(.switch)

            if !appModel.historyStore.entries.isEmpty {
                HStack {
                    Spacer()
                    Button(L10n.t("清除记录")) {
                        appModel.clearHistory()
                    }
                }
            }
        }
    }
}

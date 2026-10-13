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
        } header: {
            Text(L10n.t("当前状态"))
        } footer: {
            SettingsFooter(L10n.t("完成这两项后，WhyText 就可以在任意应用里翻译选中文本。"))
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
        } footer: {
            SettingsFooter(L10n.t("WhyText 菜单、设置和结果窗口使用的语言。不影响翻译的目标语言。"))
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section {
            Toggle(isOn: launchAtLoginBinding) {
                SettingsRowLabel(L10n.t("登录时自动启动"), subtitle: L10n.t("登录 Mac 后自动在菜单栏运行，快捷键随时可用。"))
            }
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
        } header: {
            Text(L10n.t("启动"))
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
                    subtitle: L10n.t("在菜单栏「最近」里找回之前的结果；同样的文字再查一次时直接使用记录，不再请求服务商。")
                )
            }
            .toggleStyle(.switch)

            LabeledContent {
                Button(L10n.t("清除记录")) {
                    appModel.clearHistory()
                }
                .disabled(appModel.historyStore.entries.isEmpty)
            } label: {
                CaptionText(text: L10n.f(
                    "仅保存在本机，最多 %1$@ 条（当前 %2$@ 条）。关闭后会清除已有记录。",
                    String(HistoryStore.capacity),
                    String(appModel.historyStore.entries.count)
                ))
            }
        } header: {
            Text(L10n.t("最近记录"))
        }
    }
}

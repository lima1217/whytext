import AppKit
import SwiftUI
import WhyTextCore

struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showPermissionDiagnostics = false
    @State private var launchAtLoginState = LaunchAtLogin.state
    @State private var launchAtLoginError: String?

    var body: some View {
        SettingsPage {
            interfaceLanguageCard
            overviewCard
            shortcutCard
            startupCard
            behaviorCard
            languageCard
            historyCard
            translationWindowCard
            accessibilityCard
            updatesCard
        }
    }

    private var interfaceLanguageCard: some View {
        SettingsCard(L10n.t("界面语言"), subtitle: L10n.t("WhyText 菜单、设置和结果窗口使用的语言。不影响翻译的目标语言。")) {
            Picker(L10n.t("界面语言"), selection: $appModel.settingsStore.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
    }

    private var overviewCard: some View {
        let status = appModel.accessibilityStatus()
        let hotKeyReady = appModel.settingsStore.hotKeyShortcut != nil && appModel.hotKeyIssue == nil
        let hotKeyBlocked = appModel.hotKeyIssue?.isBlocking == true

        return SettingsCard(L10n.t("当前状态"), subtitle: L10n.t("完成这两项后，WhyText 就可以在任意应用里翻译选中文本。")) {
            HStack(spacing: Spacing.x2) {
                StatusBadge(
                    text: hotKeyReady
                        ? L10n.t("快捷键已设置")
                        : appModel.hotKeyIssue == nil
                            ? L10n.t("未设置快捷键")
                            : (hotKeyBlocked ? L10n.t("快捷键不可用") : L10n.t("快捷键可能冲突")),
                    tone: hotKeyReady ? .success : .warning
                )

                StatusBadge(
                    text: status == .trusted ? L10n.t("辅助功能已授权") : L10n.t("需要辅助功能权限"),
                    tone: status == .trusted ? .success : .warning
                )

                Spacer()
            }
        }
    }

    // MARK: - Shortcut

    private var shortcutCard: some View {
        SettingsCard(L10n.t("快捷键"), subtitle: L10n.t("键盘触发是主入口，适合翻译网页、PDF、聊天窗口里的选中文本；没有选中文字时会弹出输入框。")) {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HotKeyRecorderView(shortcut: $appModel.settingsStore.hotKeyShortcut)
                hotKeyIssueRow(appModel.hotKeyIssue)

                Divider()

                Text(L10n.t("截图翻译"))
                    .font(AstryxFont.bodyMedium)
                HotKeyRecorderView(shortcut: $appModel.settingsStore.ocrHotKeyShortcut)
                hotKeyIssueRow(appModel.ocrHotKeyIssue)
                CaptionText(text: L10n.t("WhyText 能发现与 macOS 系统快捷键的冲突，但发现不了其他应用的快捷键；如果按下没有反应，换一个组合键试试。"))
                CaptionText(text: L10n.t("框选屏幕区域，在本机识别其中的文字后翻译，适合图片、视频字幕和无法选中的界面。首次使用需要授予「屏幕录制」权限。"))
            }
        }
    }

    @ViewBuilder
    private func hotKeyIssueRow(_ issue: HotKeyIssue?) -> some View {
        if let issue {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.x2) {
                StatusDot(tone: issue.isBlocking ? .danger : .warning)
                    .accessibilityHidden(true)
                Text(issue.message)
                    .font(AstryxFont.captionM)
                    .foregroundStyle(AstryxColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Startup

    private var startupCard: some View {
        SettingsCard(L10n.t("启动"), subtitle: L10n.t("登录 Mac 后自动在菜单栏运行，快捷键随时可用。")) {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Toggle(L10n.t("登录时自动启动"), isOn: launchAtLoginBinding)
                        .disabled(launchAtLoginState == .unavailable)
                    Spacer()
                }

                switch launchAtLoginState {
                case .requiresApproval:
                    HStack(spacing: Spacing.x2) {
                        CaptionText(text: L10n.t("已在系统设置的「登录项」里被关闭，需要在那里重新允许。"))
                        Button(L10n.t("打开登录项设置")) {
                            LaunchAtLogin.openSystemSettings()
                        }
                        .buttonStyle(.quiet)
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
        // The user can flip it in System Settings while we're open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginState = LaunchAtLogin.state
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

    // MARK: - Behavior

    private var behaviorCard: some View {
        SettingsCard(L10n.t("操作气泡"), subtitle: L10n.t("适合鼠标选中后顺手点击；关闭后只保留快捷键触发。")) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(L10n.t("选中文本后显示操作气泡"), isOn: $appModel.settingsStore.autoPopupOnSelection)
                Spacer()
            }
        }
    }

    // MARK: - Language

    private var languageCard: some View {
        SettingsCard(L10n.t("翻译方向"), subtitle: L10n.t("自动判断原文语言：已是母语的译成第二语言，其他语言一律译成母语。结果窗口里也可以临时改选。")) {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                Picker(L10n.t("母语"), selection: $appModel.settingsStore.primaryLanguage) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker(L10n.t("第二语言"), selection: $appModel.settingsStore.secondaryLanguage) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                CaptionText(text: L10n.t("翻译提示词里的 {{target}} 会替换成本次的目标语言。"))
            }
        }
    }

    // MARK: - History

    private var historyCard: some View {
        SettingsCard(L10n.t("最近记录"), subtitle: L10n.t("在菜单栏「最近」里找回之前的结果；同样的文字再查一次时直接使用记录，不再请求服务商。")) {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Toggle(L10n.t("保存最近的翻译和解释"), isOn: $appModel.settingsStore.saveHistory)
                    Spacer()
                    Button(L10n.t("清除记录")) {
                        appModel.clearHistory()
                    }
                    .buttonStyle(.quiet)
                    .disabled(appModel.historyStore.entries.isEmpty)
                }

                CaptionText(text: L10n.f(
                    "仅保存在本机，最多 %1$@ 条（当前 %2$@ 条）。关闭后会清除已有记录。",
                    String(HistoryStore.capacity),
                    String(appModel.historyStore.entries.count)
                ))
            }
        }
    }

    // MARK: - Translation Window

    private var translationWindowCard: some View {
        SettingsCard(L10n.t("翻译窗口"), subtitle: L10n.t("调整结果窗口正文的阅读尺寸。")) {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HStack {
                    Text(L10n.t("文字大小"))

                    Spacer()

                    Text("\(Int(appModel.settingsStore.translationFontSize)) pt")
                        .font(.system(size: SettingsUI.captionSize, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(AstryxColor.textSecondary)
                }

                Slider(
                    value: $appModel.settingsStore.translationFontSize,
                    in: 13...24,
                    step: 1
                )
            }
        }
    }

    // MARK: - Updates

    private var updatesCard: some View {
        let checker = appModel.updateChecker

        return SettingsCard(L10n.t("更新"), subtitle: L10n.t("从 GitHub Releases 查询最新版本；有新版本时菜单栏会提示，下载和安装需要手动完成。")) {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Toggle(L10n.t("每天自动检查更新"), isOn: $appModel.settingsStore.autoCheckForUpdates)
                    Spacer()
                    Text(L10n.f("当前版本 %@", checker.currentVersion?.description ?? L10n.t("开发版")))
                        .font(AstryxFont.captionM)
                        .foregroundStyle(AstryxColor.textSecondary)
                }

                HStack(spacing: Spacing.x2) {
                    Button(checker.status == .checking ? L10n.t("检查中…") : L10n.t("立即检查")) {
                        Task { await checker.check() }
                    }
                    .buttonStyle(.quiet)
                    .disabled(checker.status == .checking)

                    if checker.availableUpdate != nil {
                        Button(L10n.t("前往下载")) {
                            checker.openDownloadPage()
                        }
                        .buttonStyle(.quiet(tint: Color.accentColor))
                    }

                    if let statusText = updateStatusText(checker) {
                        CaptionText(text: statusText)
                    }

                    Spacer()
                }
            }
        }
    }

    private func updateStatusText(_ checker: UpdateChecker) -> String? {
        switch checker.status {
        case .idle, .checking:
            return nil
        case .upToDate:
            return L10n.t("已是最新版本")
        case .updateAvailable:
            return checker.availableUpdate.map { L10n.f("发现新版本 %@", $0.version.description) }
        case .failed(let message):
            return L10n.f("检查失败：%@", message)
        }
    }

    // MARK: - Accessibility

    private var accessibilityCard: some View {
        SettingsCard(L10n.t("辅助功能权限"), subtitle: L10n.t("macOS 需要授权后，应用才能读取其他 App 中的选中文本。")) {
            TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                let status = appModel.accessibilityStatus()

                VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                    HStack {
                        StatusBadge(
                            text: status == .trusted ? L10n.t("已授权") : L10n.t("未授权"),
                            tone: status == .trusted ? .success : .warning
                        )

                        Spacer()
                    }

                    if status != .trusted {
                        CaptionText(text: L10n.t("授权后如果仍读取不到选中文本，先重启 WhyText，再使用诊断查看当前 App 是否暴露选区。"))
                    }

                    HStack(spacing: Spacing.x2) {
                        Button(L10n.t("请求授权")) {
                            appModel.requestAccessibilityPermissionPrompt()
                        }
                        .buttonStyle(.quiet)

                        Button(L10n.t("打开系统设置")) {
                            appModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.quiet)
                    }

                    DisclosureGroup(L10n.t("诊断"), isExpanded: $showPermissionDiagnostics) {
                        VStack(alignment: .leading, spacing: Spacing.x2) {
                            LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "(unknown)")

                            LabeledContent(L10n.t("路径")) {
                                Text(Bundle.main.bundleURL.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .foregroundStyle(AstryxColor.textSecondary)
                            }

                            HStack(spacing: Spacing.x2) {
                                Button(L10n.t("立即诊断")) {
                                    appModel.runSelectionDiagnostics()
                                }
                                .buttonStyle(.quiet)

                                Button(appModel.selectionDiagnosticsPending ? L10n.t("2秒后诊断（进行中）") : L10n.t("2秒后诊断")) {
                                    appModel.runSelectionDiagnosticsWithDelay(seconds: 2.0)
                                }
                                .buttonStyle(.quiet)
                                .disabled(appModel.selectionDiagnosticsPending)

                                if !appModel.selectionDiagnosticsReport.isEmpty {
                                    Button(L10n.t("复制诊断结果")) {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(appModel.selectionDiagnosticsReport, forType: .string)
                                    }
                                    .buttonStyle(.quiet)
                                }

                                Button(L10n.t("重启 WhyText")) {
                                    appModel.relaunchApp()
                                }
                                .buttonStyle(.quiet)
                            }

                            if let updatedAt = appModel.selectionDiagnosticsUpdatedAt {
                                Text(L10n.f("最近诊断：%@", updatedAt.formatted(date: .abbreviated, time: .standard)))
                                    .font(AstryxFont.captionM)
                                    .foregroundStyle(AstryxColor.textSecondary)
                            }

                            if !appModel.selectionDiagnosticsTextPreview.isEmpty {
                                Text(L10n.f("选中文本预览：%@", appModel.selectionDiagnosticsTextPreview))
                                    .font(AstryxFont.captionM)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }

                            if !appModel.selectionDiagnosticsReport.isEmpty {
                                ScrollView {
                                    Text(appModel.selectionDiagnosticsReport)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 180)
                                .padding(Spacing.x2)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: Radius.concentric(outer: SettingsUI.cornerRadius, padding: Spacing.x4),
                                        style: .continuous
                                    )
                                    .fill(SettingsUI.fieldBackground)
                                )
                                .hairlineBorder(
                                    cornerRadius: Radius.concentric(outer: SettingsUI.cornerRadius, padding: Spacing.x4)
                                )
                            }
                        }
                        .padding(.top, Spacing.x1_5)
                    }
                }
                .padding(.top, Spacing.x1)
            }
        }
    }
}

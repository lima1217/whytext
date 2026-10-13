import SwiftUI
import WhyTextCore

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsPage(.shortcuts) {
            Section {
                LabeledContent(L10n.t("翻译选中文本")) {
                    HotKeyRecorderView(shortcut: $appModel.settingsStore.hotKeyShortcut)
                }
                HotKeyIssueRow(issue: appModel.hotKeyIssue)
            } footer: {
                SettingsFooter(L10n.t("键盘触发是主入口，适合翻译网页、PDF、聊天窗口里的选中文本；没有选中文字时会弹出输入框。"))
            }

            Section {
                LabeledContent(L10n.t("截图翻译")) {
                    HotKeyRecorderView(shortcut: $appModel.settingsStore.ocrHotKeyShortcut)
                }
                HotKeyIssueRow(issue: appModel.ocrHotKeyIssue)
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.x1_5) {
                    SettingsFooter(L10n.t("框选屏幕区域，在本机识别其中的文字后翻译，适合图片、视频字幕和无法选中的界面。首次使用需要授予「屏幕录制」权限。"))
                    SettingsFooter(L10n.t("WhyText 能发现与 macOS 系统快捷键的冲突，但发现不了其他应用的快捷键；如果按下没有反应，换一个组合键试试。"))
                }
            }

            Section {
                Toggle(isOn: $appModel.settingsStore.autoPopupOnSelection) {
                    SettingsRowLabel(
                        L10n.t("选中文本后显示操作气泡"),
                        subtitle: L10n.t("适合鼠标选中后顺手点击；关闭后只保留快捷键触发。")
                    )
                }
                .toggleStyle(.switch)
            } header: {
                Text(L10n.t("操作气泡"))
            }
        }
    }
}

private struct HotKeyIssueRow: View {
    var issue: HotKeyIssue?

    var body: some View {
        if let issue {
            let tone: Tone = issue.isBlocking ? .danger : .warning
            HStack(alignment: .firstTextBaseline, spacing: Spacing.x2) {
                Image(systemName: tone.icon)
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
                Text(issue.message)
                    .font(AstryxFont.captionM)
                    .foregroundStyle(AstryxColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}

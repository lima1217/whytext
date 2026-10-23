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
                LabeledContent(L10n.t("截图翻译")) {
                    HotKeyRecorderView(shortcut: $appModel.settingsStore.ocrHotKeyShortcut)
                }
                HotKeyIssueRow(issue: appModel.ocrHotKeyIssue)
            }

            Section {
                Toggle(L10n.t("选中文本后显示操作气泡"), isOn: $appModel.settingsStore.autoPopupOnSelection)
                    .toggleStyle(.switch)
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

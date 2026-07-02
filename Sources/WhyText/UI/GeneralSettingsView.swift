import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showPermissionDiagnostics = false

    var body: some View {
        SettingsPage {
            overviewCard
            shortcutCard
            behaviorCard
            translationWindowCard
            accessibilityCard
        }
    }

    private var overviewCard: some View {
        let status = appModel.accessibilityStatus()
        let hotKeyReady = appModel.settingsStore.hotKeyShortcut != nil

        return SettingsCard("当前状态", subtitle: "完成这两项后，WhyText 就可以在任意应用里翻译选中文本。") {
            HStack(spacing: Spacing.x2) {
                StatusBadge(
                    text: hotKeyReady ? "快捷键已设置" : "未设置快捷键",
                    tone: hotKeyReady ? .success : .warning
                )

                StatusBadge(
                    text: status == .trusted ? "辅助功能已授权" : "需要辅助功能权限",
                    tone: status == .trusted ? .success : .warning
                )

                Spacer()
            }
        }
    }

    // MARK: - Shortcut

    private var shortcutCard: some View {
        SettingsCard("快捷键", subtitle: "键盘触发是主入口，适合翻译网页、PDF、聊天窗口里的选中文本。") {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HotKeyRecorderView(shortcut: $appModel.settingsStore.hotKeyShortcut)
            }
        }
    }

    // MARK: - Behavior

    private var behaviorCard: some View {
        SettingsCard("选区浮点", subtitle: "适合鼠标选中后顺手点击，关闭后只保留快捷键触发。") {
            HStack(alignment: .firstTextBaseline) {
                Toggle("选中文本后显示翻译按钮", isOn: $appModel.settingsStore.autoPopupOnSelection)
                Spacer()
            }
        }
    }

    // MARK: - Translation Window

    private var translationWindowCard: some View {
        SettingsCard("翻译窗口", subtitle: "调整结果窗口正文的阅读尺寸。") {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HStack {
                    Text("文字大小")

                    Spacer()

                    Text("\(Int(appModel.settingsStore.translationFontSize)) pt")
                        .font(.system(size: SettingsUI.captionSize, design: .monospaced))
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

    // MARK: - Accessibility

    private var accessibilityCard: some View {
        SettingsCard("辅助功能权限", subtitle: "macOS 需要授权后，应用才能读取其他 App 中的选中文本。") {
            TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                let status = appModel.accessibilityStatus()

                VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                    HStack {
                        StatusBadge(
                            text: status == .trusted ? "已授权" : "未授权",
                            tone: status == .trusted ? .success : .warning
                        )

                        Spacer()
                    }

                    if status != .trusted {
                        CaptionText(text: "授权后如果仍读取不到选中文本，先重启 WhyText，再使用诊断查看当前 App 是否暴露选区。")
                    }

                    HStack(spacing: Spacing.x2) {
                        Button("请求授权") {
                            appModel.requestAccessibilityPermissionPrompt()
                        }
                        .buttonStyle(.quiet)

                        Button("打开系统设置") {
                            appModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.quiet)
                    }

                    DisclosureGroup("诊断", isExpanded: $showPermissionDiagnostics) {
                        VStack(alignment: .leading, spacing: Spacing.x2) {
                            LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "(unknown)")

                            LabeledContent("路径") {
                                Text(Bundle.main.bundleURL.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .foregroundStyle(AstryxColor.textSecondary)
                            }

                            HStack(spacing: Spacing.x2) {
                                Button("立即诊断") {
                                    appModel.runSelectionDiagnostics()
                                }
                                .buttonStyle(.quiet)

                                Button(appModel.selectionDiagnosticsPending ? "2秒后诊断（进行中）" : "2秒后诊断") {
                                    appModel.runSelectionDiagnosticsWithDelay(seconds: 2.0)
                                }
                                .buttonStyle(.quiet)
                                .disabled(appModel.selectionDiagnosticsPending)

                                if !appModel.selectionDiagnosticsReport.isEmpty {
                                    Button("复制诊断结果") {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(appModel.selectionDiagnosticsReport, forType: .string)
                                    }
                                    .buttonStyle(.quiet)
                                }

                                Button("重启 WhyText") {
                                    appModel.relaunchApp()
                                }
                                .buttonStyle(.quiet)
                            }

                            if let updatedAt = appModel.selectionDiagnosticsUpdatedAt {
                                Text("最近诊断: \(updatedAt.formatted(date: .abbreviated, time: .standard))")
                                    .font(AstryxFont.captionM)
                                    .foregroundStyle(AstryxColor.textSecondary)
                            }

                            if !appModel.selectionDiagnosticsTextPreview.isEmpty {
                                Text("选中文本预览: \(appModel.selectionDiagnosticsTextPreview)")
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
                                    RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                                        .fill(SettingsUI.fieldBackground)
                                )
                                .hairlineBorder(cornerRadius: Radius.element)
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

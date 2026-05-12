import AppKit
import SwiftUI

private enum GeneralUITokens {
    static let cardSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let maxContentWidth: CGFloat = 620
    static let pagePadding: CGFloat = 20
    static let captionSize: CGFloat = 12
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showPermissionDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GeneralUITokens.cardSpacing) {
                shortcutCard
                behaviorCard
                accessibilityCard
            }
            .frame(maxWidth: GeneralUITokens.maxContentWidth)
            .padding(GeneralUITokens.pagePadding)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shortcut

    private var shortcutCard: some View {
        GroupBox("快捷键") {
            VStack(alignment: .leading, spacing: GeneralUITokens.sectionSpacing) {
                HotKeyRecorderView(shortcut: $appModel.settingsStore.hotKeyShortcut)

                Text("选中文本后按快捷键即可翻译。")
                    .font(.system(size: GeneralUITokens.captionSize))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Behavior

    private var behaviorCard: some View {
        GroupBox("行为") {
            VStack(alignment: .leading, spacing: GeneralUITokens.sectionSpacing) {
                Toggle("选中文本后自动显示翻译按钮", isOn: $appModel.settingsStore.autoPopupOnSelection)

                Text("开启后，选中文本时会在光标旁出现一个小按钮，点击即可翻译。")
                    .font(.system(size: GeneralUITokens.captionSize))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Accessibility

    private var accessibilityCard: some View {
        GroupBox("辅助功能权限") {
            TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                let status = appModel.accessibilityStatus()

                VStack(alignment: .leading, spacing: GeneralUITokens.sectionSpacing) {
                    HStack {
                        Text(status == .trusted ? "已授权" : "未授权")
                            .font(.system(size: GeneralUITokens.captionSize, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill((status == .trusted ? Color.green : Color.orange).opacity(0.16))
                            )
                            .foregroundStyle(status == .trusted ? .green : .orange)

                        Spacer()
                    }

                    if status != .trusted {
                        Text("WhyText 需要辅助功能权限来读取选中文本。")
                            .font(.system(size: GeneralUITokens.captionSize))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button("请求授权") {
                            appModel.requestAccessibilityPermissionPrompt()
                        }

                        Button("打开系统设置") {
                            appModel.openAccessibilitySettings()
                        }
                    }

                    DisclosureGroup("诊断", isExpanded: $showPermissionDiagnostics) {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "(unknown)")

                            LabeledContent("路径") {
                                Text(Bundle.main.bundleURL.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Button("立即诊断") {
                                    appModel.runSelectionDiagnostics()
                                }

                                Button(appModel.selectionDiagnosticsPending ? "2秒后诊断（进行中）" : "2秒后诊断") {
                                    appModel.runSelectionDiagnosticsWithDelay(seconds: 2.0)
                                }
                                .disabled(appModel.selectionDiagnosticsPending)

                                if !appModel.selectionDiagnosticsReport.isEmpty {
                                    Button("复制诊断结果") {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(appModel.selectionDiagnosticsReport, forType: .string)
                                    }
                                }

                                Button("重启 WhyText") {
                                    appModel.relaunchApp()
                                }
                            }

                            if let updatedAt = appModel.selectionDiagnosticsUpdatedAt {
                                Text("最近诊断: \(updatedAt.formatted(date: .abbreviated, time: .standard))")
                                    .font(.system(size: GeneralUITokens.captionSize))
                                    .foregroundStyle(.secondary)
                            }

                            if !appModel.selectionDiagnosticsTextPreview.isEmpty {
                                Text("选中文本预览: \(appModel.selectionDiagnosticsTextPreview)")
                                    .font(.system(size: GeneralUITokens.captionSize))
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
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

import AppKit
import SwiftUI
import WhyTextCore

struct PermissionsSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsPage(.permissions) {
            Section {
                // Poll: macOS doesn't notify us when the user flips the switch.
                TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                    let trusted = appModel.accessibilityStatus() == .trusted
                    LabeledContent(L10n.t("辅助功能权限")) {
                        StatusBadge(
                            text: trusted ? L10n.t("已授权") : L10n.t("未授权"),
                            tone: trusted ? .success : .warning
                        )
                    }
                }

                HStack(spacing: Spacing.x2) {
                    Spacer()
                    Button(L10n.t("请求授权")) {
                        appModel.requestAccessibilityPermissionPrompt()
                    }
                    Button(L10n.t("打开系统设置")) {
                        appModel.openAccessibilitySettings()
                    }
                    Button(L10n.t("重启 WhyText")) {
                        appModel.relaunchApp()
                    }
                }
            }

            diagnosticsSection
        }
    }

    private var diagnosticsSection: some View {
        Section {
            LabeledContent("Bundle ID") {
                Text(Bundle.main.bundleIdentifier ?? "(unknown)")
                    .textSelection(.enabled)
            }

            LabeledContent(L10n.t("路径")) {
                Text(Bundle.main.bundleURL.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: Spacing.x2) {
                Spacer()

                if !appModel.selectionDiagnosticsReport.isEmpty {
                    Button(L10n.t("复制诊断结果")) {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(appModel.selectionDiagnosticsReport, forType: .string)
                    }
                }

                if appModel.selectionDiagnosticsPending {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(L10n.t("2秒后诊断")) {
                    appModel.runSelectionDiagnosticsWithDelay(seconds: 2.0)
                }
                .disabled(appModel.selectionDiagnosticsPending)

                Button(L10n.t("立即诊断")) {
                    appModel.runSelectionDiagnostics()
                }
            }

            if hasDiagnosticsOutput {
                VStack(alignment: .leading, spacing: Spacing.x2) {
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
                        .frame(maxHeight: 200)
                        .settingsWell(padding: Spacing.x2)
                    }
                }
            }
        } header: {
            Text(L10n.t("诊断"))
        }
    }

    private var hasDiagnosticsOutput: Bool {
        appModel.selectionDiagnosticsUpdatedAt != nil
            || !appModel.selectionDiagnosticsTextPreview.isEmpty
            || !appModel.selectionDiagnosticsReport.isEmpty
    }
}

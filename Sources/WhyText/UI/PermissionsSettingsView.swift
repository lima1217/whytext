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
                    LabeledContent {
                        if trusted {
                            SetupStatus(text: L10n.t("已授权"), ready: true)
                        } else {
                            Button(L10n.t("打开系统设置")) {
                                appModel.requestAccessibilityPermissionPrompt()
                                appModel.openAccessibilitySettings()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } label: {
                        SettingsRowLabel(
                            L10n.t("辅助功能"),
                            subtitle: trusted
                                ? L10n.t("用来读取你在其他应用里选中的文字。")
                                : L10n.t("用来读取你在其他应用里选中的文字。在「辅助功能」列表里打开 WhyText 的开关即可。")
                        )
                    }
                }
            }

            diagnosticsSection
        }
    }

    @State private var showsTroubleshooting = false

    private var diagnosticsSection: some View {
        Section {
            DisclosureGroup(L10n.t("故障排查"), isExpanded: $showsTroubleshooting) {
                troubleshootingContent
            }
        }
    }

    @ViewBuilder
    private var troubleshootingContent: some View {
            LabeledContent {
                Button(L10n.t("重新打开 WhyText")) {
                    appModel.relaunchApp()
                }
            } label: {
                SettingsRowLabel(
                    L10n.t("开关已打开，这里仍显示未授权"),
                    subtitle: L10n.t("重新打开 WhyText 让授权生效。")
                )
            }

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

                // Clicking here makes WhyText frontmost, so sampling waits for the user
                // to switch back to the app whose selection fails.
                Button(L10n.t("2 秒后读取选中文字")) {
                    appModel.runSelectionDiagnosticsWithDelay(seconds: 2.0)
                }
                .disabled(appModel.selectionDiagnosticsPending)
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
    }

    private var hasDiagnosticsOutput: Bool {
        appModel.selectionDiagnosticsUpdatedAt != nil
            || !appModel.selectionDiagnosticsTextPreview.isEmpty
            || !appModel.selectionDiagnosticsReport.isEmpty
    }
}

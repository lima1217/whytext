import AppKit
import SwiftUI
import WhyTextCore

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let hotKeyLabel = appModel.settingsStore.hotKeyShortcut?.displayString ?? L10n.t("未设置")
        let providerName = appModel.settingsStore.selectedProvider?.name ?? L10n.t("未配置")
        let accessibilityReady = appModel.accessibilityStatus() == .trusted

        Button(L10n.t("翻译选中文本") + "  \(hotKeyLabel)") {
            appModel.openPanelFromMenu()
        }

        if appModel.hotKeyIssue != nil || appModel.ocrHotKeyIssue != nil {
            Button {
                appModel.openSettingsWindow()
            } label: {
                Label(L10n.t("快捷键需要处理，点此查看…"), systemImage: "exclamationmark.triangle")
            }
        }

        Button(L10n.t("输入文字翻译…")) {
            appModel.openManualInput()
        }

        Button(ocrMenuTitle) {
            appModel.startScreenTextCapture()
        }

        if !appModel.historyStore.entries.isEmpty {
            Menu(L10n.t("最近")) {
                ForEach(appModel.historyStore.entries.prefix(Self.recentMenuLimit)) { entry in
                    Button {
                        appModel.showHistoryEntry(entry)
                    } label: {
                        Label(Self.menuTitle(for: entry), systemImage: entry.key.action == .translate ? "character.bubble" : "questionmark.circle")
                    }
                }

                Divider()

                Button(L10n.t("清除最近记录")) {
                    appModel.clearHistory()
                }
            }
        }

        Divider()

        Label(L10n.f("服务商：%@", providerName), systemImage: "network")
        Label(accessibilityReady ? L10n.t("辅助功能已授权") : L10n.t("需要辅助功能权限"), systemImage: accessibilityReady ? "checkmark.circle" : "exclamationmark.triangle")

        Divider()

        if let update = appModel.updateChecker.availableUpdate {
            updateMenuItem(update)
        }

        Button(L10n.t("设置…")) {
            appModel.openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button(L10n.t("退出")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private func updateMenuItem(_ update: UpdateChecker.AvailableUpdate) -> some View {
        let checker = appModel.updateChecker
        switch checker.installState {
        case .downloading(let fraction):
            Button(L10n.f("正在下载更新（%@）…", "\(Int(fraction * 100))%")) {}
                .disabled(true)
        case .installing:
            Button(L10n.t("正在安装更新…")) {}
                .disabled(true)
        case .failed:
            Button(L10n.t("更新失败，前往下载页…")) {
                checker.openDownloadPage()
            }
        case .idle:
            if checker.canInstallUpdate {
                Button(L10n.f("更新到 %@…", update.version.description)) {
                    checker.installUpdate()
                }
            } else {
                Button(L10n.f("有新版本 %@，前往下载…", update.version.description)) {
                    checker.openDownloadPage()
                }
            }
        }
    }

    private var ocrMenuTitle: String {
        if let shortcut = appModel.settingsStore.ocrHotKeyShortcut {
            return L10n.t("截图翻译…") + "  \(shortcut.displayString)"
        }
        return L10n.t("截图翻译…")
    }

    private static let recentMenuLimit = 20

    private static func menuTitle(for entry: HistoryEntry) -> String {
        let flattened = entry.sourceText
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flattened.count > 36 ? String(flattened.prefix(36)) + "…" : flattened
    }
}

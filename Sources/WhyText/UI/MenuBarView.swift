import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let hotKeyLabel = appModel.settingsStore.hotKeyShortcut?.displayString ?? "未设置"
        let providerName = appModel.settingsStore.selectedProvider?.name ?? "未配置"
        let accessibilityReady = appModel.accessibilityStatus() == .trusted

        Button("翻译选中文本  \(hotKeyLabel)") {
            appModel.openPanelFromMenu()
        }

        Button("输入文字翻译…") {
            appModel.openManualInput()
        }

        Button(ocrMenuTitle) {
            appModel.startScreenTextCapture()
        }

        if !appModel.historyStore.entries.isEmpty {
            Menu("最近") {
                ForEach(appModel.historyStore.entries.prefix(Self.recentMenuLimit)) { entry in
                    Button {
                        appModel.showHistoryEntry(entry)
                    } label: {
                        Label(Self.menuTitle(for: entry), systemImage: entry.key.action == .translate ? "character.bubble" : "questionmark.circle")
                    }
                }

                Divider()

                Button("清除最近记录") {
                    appModel.clearHistory()
                }
            }
        }

        Divider()

        Label("服务商：\(providerName)", systemImage: "network")
        Label(accessibilityReady ? "辅助功能已授权" : "需要辅助功能权限", systemImage: accessibilityReady ? "checkmark.circle" : "exclamationmark.triangle")

        Divider()

        if let update = appModel.updateChecker.availableUpdate {
            Button("有新版本 \(update.version.description)，前往下载…") {
                appModel.updateChecker.openDownloadPage()
            }
        }

        Button("设置…") {
            appModel.openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("退出") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var ocrMenuTitle: String {
        if let shortcut = appModel.settingsStore.ocrHotKeyShortcut {
            return "截图翻译…  \(shortcut.displayString)"
        }
        return "截图翻译…"
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

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

        Divider()

        Label("Provider: \(providerName)", systemImage: "network")
        Label(accessibilityReady ? "辅助功能已授权" : "需要辅助功能权限", systemImage: accessibilityReady ? "checkmark.circle" : "exclamationmark.triangle")

        Divider()

        Button("设置…") {
            appModel.openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("退出") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

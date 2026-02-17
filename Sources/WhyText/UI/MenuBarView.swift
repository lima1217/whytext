import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let hotKeyLabel = appModel.settingsStore.hotKeyShortcut?.displayString ?? "未设置"

        Button("翻译选中文本  \(hotKeyLabel)") {
            appModel.openPanelFromMenu()
        }

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

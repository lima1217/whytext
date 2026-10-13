import AppKit
import SwiftUI
import WhyTextCore

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let hotKeyLabel = appModel.settingsStore.hotKeyShortcut?.displayString ?? L10n.t("未设置")
        let providerName = appModel.settingsStore.selectedProvider?.name ?? L10n.t("未配置")
        let accessibilityReady = appModel.accessibilityStatus() == .trusted

        Button {
            appModel.openPanelFromMenu()
        } label: {
            Label(L10n.t("翻译选中文本") + "  \(hotKeyLabel)", systemImage: "text.cursor")
        }

        if appModel.hotKeyIssue != nil || appModel.ocrHotKeyIssue != nil {
            Button {
                appModel.openSettingsWindow()
            } label: {
                Label(L10n.t("快捷键需要处理，点此查看…"), systemImage: "exclamationmark.triangle.fill")
            }
        }

        Button {
            appModel.openManualInput()
        } label: {
            Label(L10n.t("输入文字翻译…"), systemImage: "keyboard")
        }

        Button {
            appModel.startScreenTextCapture()
        } label: {
            Label(ocrMenuTitle, systemImage: "text.viewfinder")
        }

        if !appModel.historyStore.entries.isEmpty {
            Menu {
                ForEach(appModel.historyStore.entries.prefix(Self.recentMenuLimit)) { entry in
                    Button {
                        appModel.showHistoryEntry(entry)
                    } label: {
                        Label(Self.menuTitle(for: entry), systemImage: entry.key.action == .translate ? "character.bubble" : "questionmark.circle")
                    }
                }

                Divider()

                Button {
                    appModel.clearHistory()
                } label: {
                    Label(L10n.t("清除最近记录"), systemImage: "trash")
                }
            } label: {
                Label(L10n.t("最近"), systemImage: "clock.arrow.circlepath")
            }
        }

        Divider()

        Label(L10n.f("服务商：%@", providerName), systemImage: "network")
        if accessibilityReady {
            Label(L10n.t("辅助功能已授权"), systemImage: "checkmark.shield")
        } else {
            Button {
                appModel.openSettingsWindow()
            } label: {
                Label(L10n.t("需要辅助功能权限"), systemImage: "exclamationmark.shield")
            }
        }

        Divider()

        if let update = appModel.updateChecker.availableUpdate {
            updateMenuItem(update)
        }

        Button {
            appModel.openSettingsWindow()
        } label: {
            Label(L10n.t("设置…"), systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            NSApp.terminate(nil)
        } label: {
            Label(L10n.t("退出"), systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private func updateMenuItem(_ update: UpdateChecker.AvailableUpdate) -> some View {
        let checker = appModel.updateChecker
        switch checker.installState {
        case .downloading(let fraction):
            Button {} label: {
                Label(L10n.f("正在下载更新（%@）…", "\(Int(fraction * 100))%"), systemImage: "arrow.down.circle")
            }
                .disabled(true)
        case .installing:
            Button {} label: {
                Label(L10n.t("正在安装更新…"), systemImage: "arrow.triangle.2.circlepath")
            }
                .disabled(true)
        case .failed:
            Button {
                checker.openDownloadPage()
            } label: {
                Label(L10n.t("更新失败，前往下载页…"), systemImage: "exclamationmark.arrow.circlepath")
            }
        case .idle:
            if checker.canInstallUpdate {
                Button {
                    checker.installUpdate()
                } label: {
                    Label(L10n.f("更新到 %@…", update.version.description), systemImage: "sparkles")
                }
            } else {
                Button {
                    checker.openDownloadPage()
                } label: {
                    Label(L10n.f("有新版本 %@，前往下载…", update.version.description), systemImage: "sparkles")
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

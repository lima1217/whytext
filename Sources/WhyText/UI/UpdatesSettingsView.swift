import SwiftUI
import WhyTextCore

struct UpdatesSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let checker = appModel.updateChecker

        SettingsPage(.updates) {
            Section {
                LabeledContent {
                    HStack(spacing: Spacing.x2) {
                        if checker.status == .checking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button(checker.status == .checking ? L10n.t("检查中…") : L10n.t("立即检查")) {
                            Task { await checker.check() }
                        }
                        .disabled(checker.status == .checking)
                    }
                } label: {
                    SettingsRowLabel(
                        L10n.f("当前版本 %@", checker.currentVersion?.description ?? L10n.t("开发版")),
                        subtitle: updateStatusText(checker)
                    )
                }

                if let update = checker.availableUpdate {
                    LabeledContent {
                        HStack(spacing: Spacing.x2) {
                            Button(checker.canInstallUpdate ? L10n.t("查看更新内容") : L10n.t("前往下载")) {
                                checker.openDownloadPage()
                            }
                            if checker.canInstallUpdate {
                                Button(L10n.t("立即更新")) {
                                    checker.installUpdate()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(checker.isInstalling)
                            }
                        }
                    } label: {
                        Label {
                            Text(L10n.f("发现新版本 %@", update.version.description))
                                .font(AstryxFont.bodyMedium)
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                Toggle(L10n.t("每天自动检查更新"), isOn: $appModel.settingsStore.autoCheckForUpdates)
                    .toggleStyle(.switch)
            } footer: {
                SettingsFooter(L10n.t("从 GitHub Releases 查询最新版本。点「立即更新」会下载新版本、确认签名与当前 App 一致后替换并自动重启。"))
            }
        }
    }

    private func updateStatusText(_ checker: UpdateChecker) -> String? {
        switch checker.installState {
        case .downloading(let fraction):
            return L10n.f("正在下载更新（%@）…", "\(Int(fraction * 100))%")
        case .installing:
            return L10n.t("正在安装更新…")
        case .failed(let message):
            return L10n.f("更新失败：%@", message)
        case .idle:
            break
        }

        switch checker.status {
        case .idle, .checking, .updateAvailable:
            return nil
        case .upToDate:
            return L10n.t("已是最新版本")
        case .failed(let message):
            return L10n.f("检查失败：%@", message)
        }
    }
}

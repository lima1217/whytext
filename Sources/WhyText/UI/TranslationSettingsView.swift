import SwiftUI
import WhyTextCore

struct TranslationSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsPage(.translation) {
            Section {
                languagePicker(L10n.t("母语"), selection: $appModel.settingsStore.primaryLanguage)
                languagePicker(L10n.t("第二语言"), selection: $appModel.settingsStore.secondaryLanguage)
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.x1_5) {
                    SettingsFooter(L10n.t("自动判断原文语言：已是母语的译成第二语言，其他语言一律译成母语。结果窗口里也可以临时改选。"))
                    SettingsFooter(L10n.t("翻译提示词里的 {{target}} 会替换成本次的目标语言。"))
                }
            }

            Section {
                LabeledContent(L10n.t("文字大小")) {
                    HStack(spacing: Spacing.x3) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(AstryxColor.textSecondary)
                            .accessibilityHidden(true)
                        Slider(value: $appModel.settingsStore.translationFontSize, in: 13...24, step: 1)
                            .frame(width: 200)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(AstryxColor.textSecondary)
                            .accessibilityHidden(true)
                        Text("\(Int(appModel.settingsStore.translationFontSize)) pt")
                            .font(AstryxFont.captionM)
                            .monospacedDigit()
                            .foregroundStyle(AstryxColor.textSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text(L10n.t("翻译窗口"))
            } footer: {
                SettingsFooter(L10n.t("调整结果窗口正文的阅读尺寸。"))
            }
        }
    }

    private func languagePicker(_ title: String, selection: Binding<TranslationLanguage>) -> some View {
        Picker(title, selection: selection) {
            ForEach(TranslationLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        }
    }
}

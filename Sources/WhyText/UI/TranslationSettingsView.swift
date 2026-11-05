import SwiftUI
import WhyTextCore

struct TranslationSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsPage(.translation) {
            Section {
                languagePicker(L10n.t("母语"), selection: $appModel.settingsStore.primaryLanguage)
                languagePicker(L10n.t("第二语言"), selection: $appModel.settingsStore.secondaryLanguage)
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

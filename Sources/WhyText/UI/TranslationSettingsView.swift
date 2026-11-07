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
                CaptionText(text: L10n.f(
                    "「%1$@」的文字译成「%2$@」，其他语言都译成「%1$@」。",
                    appModel.settingsStore.primaryLanguage.displayName,
                    appModel.settingsStore.secondaryLanguage.displayName
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(appModel.settingsStore.translationFontSize.formatted(.number.precision(.fractionLength(0))) + " pt")
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

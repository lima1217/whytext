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

            Section {
                glassTintSlider(L10n.t("浅色模式玻璃色调"), value: $appModel.settingsStore.lightGlassTint)
                glassTintSlider(L10n.t("深色模式玻璃色调"), value: $appModel.settingsStore.darkGlassTint)
                CaptionText(text: L10n.t("调低色调，玻璃更通透；为 0 时只保留模糊、边缘和阴影。"))
            }
        }
    }

    private func glassTintSlider(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: Spacing.x3) {
                Slider(value: value, in: SettingsStore.glassTintRange, step: 0.05)
                    .frame(width: 200)
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(AstryxFont.captionM)
                    .monospacedDigit()
                    .foregroundStyle(AstryxColor.textSecondary)
                    .frame(width: 40, alignment: .trailing)
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

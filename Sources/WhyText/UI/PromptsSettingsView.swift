import SwiftUI
import WhyTextCore

private enum PromptUITokens {
    static let editorHeight: CGFloat = 180
}

struct PromptsSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsPage(.prompts) {
            PromptTemplateCard(
                title: L10n.t("翻译提示词"),
                subtitle: L10n.t("决定语气、格式与输出边界。模板必须包含 {{text}}，运行时会替换为你选中的原文；{{target}} 会替换为自动判断的目标语言（如「英文」「简体中文」）。"),
                template: $appModel.settingsStore.translatePromptTemplate,
                defaultTemplate: SettingsStore.defaultTranslatePromptTemplate,
                onReset: {
                    appModel.settingsStore.resetTranslatePromptTemplateToDefault()
                }
            )

            PromptTemplateCard(
                title: L10n.t("解释提示词"),
                subtitle: L10n.t("选中气泡上的问号会用这份模板解释原文，而不是翻译。模板必须包含 {{text}}；{{target}} 会替换为你的母语。"),
                template: $appModel.settingsStore.explainPromptTemplate,
                defaultTemplate: SettingsStore.defaultExplainPromptTemplate,
                onReset: {
                    appModel.settingsStore.resetExplainPromptTemplateToDefault()
                }
            )
        }
    }
}

private struct PromptTemplateCard: View {
    let title: String
    let subtitle: String
    @Binding var template: String
    let defaultTemplate: String
    let onReset: () -> Void

    var body: some View {
        Section {
            editor

            HStack(spacing: Spacing.x2) {
                StatusBadge(
                    text: hasPlaceholder ? L10n.t("占位符有效") : L10n.t("缺少 {{text}}"),
                    tone: hasPlaceholder ? .success : .danger
                )

                Text(L10n.f("%@ 字符", String(templateCharacterCount)))
                    .font(AstryxFont.captionM)
                    .monospacedDigit()
                    .foregroundStyle(AstryxColor.textSecondary)

                Spacer()

                Button(L10n.t("插入 {{text}}")) {
                    insertTextPlaceholder()
                }
                .disabled(hasPlaceholder)

                Button(L10n.t("恢复默认")) {
                    onReset()
                }
                .disabled(isDefaultTemplate)
            }
        } header: {
            Text(title)
        } footer: {
            SettingsFooter(subtitle)
        }
    }

    private var editor: some View {
        TextEditor(text: $template)
            .font(AstryxFont.bodyMono)
            .scrollContentBackground(.hidden)
            .frame(height: PromptUITokens.editorHeight)
            .settingsWell(padding: Spacing.x2)
    }

    private var templateCharacterCount: Int {
        template.count
    }

    private var isDefaultTemplate: Bool {
        template.trimmingCharacters(in: .whitespacesAndNewlines)
            == defaultTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPlaceholder: Bool {
        template.contains("{{text}}")
    }

    private func insertTextPlaceholder() {
        let token = "{{text}}"
        if template.contains(token) {
            return
        }

        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            template = token
        } else {
            template = "\(trimmed)\n\n\(token)"
        }
    }
}

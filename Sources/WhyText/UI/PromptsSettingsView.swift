import SwiftUI

private enum PromptUITokens {
    static let editorHeight: CGFloat = 180
}

struct PromptsSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsPage {
            PromptTemplateCard(
                title: "翻译提示词",
                subtitle: "决定语气、格式与输出边界。模板必须包含 {{text}}，运行时会替换为你选中的原文。",
                template: $appModel.settingsStore.translatePromptTemplate,
                defaultTemplate: SettingsStore.defaultTranslatePromptTemplate,
                onReset: {
                    appModel.settingsStore.resetTranslatePromptTemplateToDefault()
                }
            )

            PromptTemplateCard(
                title: "解释提示词",
                subtitle: "选中气泡上的问号会用这份模板解释原文，而不是翻译。模板必须包含 {{text}}。",
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
        SettingsCard(title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: SettingsUI.fieldSpacing) {
                HStack {
                    StatusBadge(
                        text: hasPlaceholder ? "占位符有效" : "缺少 {{text}}",
                        tone: hasPlaceholder ? .success : .danger
                    )

                    Spacer()
                }

                editor

                HStack(spacing: Spacing.x2_5) {
                    Text("\(templateCharacterCount) 字符")
                        .font(AstryxFont.captionM)
                        .foregroundStyle(AstryxColor.textSecondary)

                    Spacer()

                    Button("插入 {{text}}") {
                        insertTextPlaceholder()
                    }
                    .buttonStyle(.quiet)

                    Button("恢复默认") {
                        onReset()
                    }
                    .buttonStyle(.quiet)
                    .disabled(isDefaultTemplate)
                }
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $template)
            .font(AstryxFont.bodyMono)
            .frame(height: PromptUITokens.editorHeight)
            .padding(Spacing.x2_5)
            .background(
                RoundedRectangle(
                    cornerRadius: Radius.concentric(outer: SettingsUI.cornerRadius, padding: Spacing.x4),
                    style: .continuous
                )
                .fill(SettingsUI.fieldBackground)
            )
            .hairlineBorder(
                cornerRadius: Radius.concentric(outer: SettingsUI.cornerRadius, padding: Spacing.x4),
                lineWidth: 1
            )
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

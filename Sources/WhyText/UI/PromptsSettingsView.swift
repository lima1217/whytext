import SwiftUI

private enum PromptUITokens {
    static let editorHeight: CGFloat = 240
}

struct PromptsSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsPage {
            promptCard
        }
    }

    private var promptCard: some View {
        SettingsCard("翻译提示词", subtitle: "决定语气、格式与输出边界。模板必须包含 {{text}}，运行时会替换为你选中的原文。") {
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
                        appModel.settingsStore.resetTranslatePromptTemplateToDefault()
                    }
                    .buttonStyle(.quiet)
                    .disabled(isDefaultTemplate)
                }
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $appModel.settingsStore.translatePromptTemplate)
            .font(AstryxFont.bodyMono)
            .frame(height: PromptUITokens.editorHeight)
            .padding(Spacing.x2_5)
            .background(
                RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                    .fill(SettingsUI.fieldBackground)
            )
            .hairlineBorder(cornerRadius: Radius.element, lineWidth: 1)
    }

    private var templateCharacterCount: Int {
        appModel.settingsStore.translatePromptTemplate.count
    }

    private var isDefaultTemplate: Bool {
        appModel.settingsStore.translatePromptTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines)
        == SettingsStore.defaultTranslatePromptTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPlaceholder: Bool {
        appModel.settingsStore.translatePromptTemplate.contains("{{text}}")
    }

    private func insertTextPlaceholder() {
        let token = "{{text}}"
        if appModel.settingsStore.translatePromptTemplate.contains(token) {
            return
        }

        let trimmed = appModel.settingsStore.translatePromptTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            appModel.settingsStore.translatePromptTemplate = token
        } else {
            appModel.settingsStore.translatePromptTemplate = "\(trimmed)\n\n\(token)"
        }
    }
}

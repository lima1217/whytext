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

                HStack(spacing: 10) {
                    Text("\(templateCharacterCount) 字符")
                        .font(.system(size: SettingsUI.captionSize))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button("插入 {{text}}") {
                        insertTextPlaceholder()
                    }
                    .buttonStyle(.bordered)

                    Button("恢复默认") {
                        appModel.settingsStore.resetTranslatePromptTemplateToDefault()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDefaultTemplate)
                }
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $appModel.settingsStore.translatePromptTemplate)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .frame(height: PromptUITokens.editorHeight)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SettingsUI.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
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

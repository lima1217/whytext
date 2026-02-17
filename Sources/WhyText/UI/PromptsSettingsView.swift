import SwiftUI

private enum PromptUITokens {
    static let cardSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let maxContentWidth: CGFloat = 620
    static let pagePadding: CGFloat = 20
    static let captionSize: CGFloat = 12
    static let editorHeight: CGFloat = 240
    static let editorCornerRadius: CGFloat = 10
}

struct PromptsSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PromptUITokens.cardSpacing) {
                promptCard
            }
            .frame(maxWidth: PromptUITokens.maxContentWidth)
            .padding(PromptUITokens.pagePadding)
            .frame(maxWidth: .infinity)
        }
    }

    private var promptCard: some View {
        GroupBox("翻译提示词") {
            VStack(alignment: .leading, spacing: PromptUITokens.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("决定语气、格式与输出边界")
                        .font(.system(size: 13, weight: .medium))

                    Text("必须包含 {{text}}，它会在运行时替换为你选中的原文。")
                        .font(.system(size: PromptUITokens.captionSize))
                        .foregroundStyle(.secondary)
                }

                editor

                HStack(spacing: 10) {
                    Text("\(templateCharacterCount) 字符")
                        .font(.system(size: PromptUITokens.captionSize))
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
            .padding(.top, 4)
        }
    }

    private var editor: some View {
        TextEditor(text: $appModel.settingsStore.translatePromptTemplate)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .frame(height: PromptUITokens.editorHeight)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: PromptUITokens.editorCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.045), Color.primary.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: PromptUITokens.editorCornerRadius, style: .continuous)
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

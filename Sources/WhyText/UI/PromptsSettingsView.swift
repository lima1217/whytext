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
                template: $appModel.settingsStore.translatePromptTemplate,
                defaultTemplate: SettingsStore.defaultTranslatePromptTemplate,
                onReset: {
                    appModel.settingsStore.resetTranslatePromptTemplateToDefault()
                }
            )

            PromptTemplateCard(
                title: L10n.t("解释提示词"),
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
    @Binding var template: String
    let defaultTemplate: String
    let onReset: () -> Void
    @State private var confirmingReset = false

    var body: some View {
        Section {
            editor

            HStack(spacing: Spacing.x2) {
                if !hasPlaceholder {
                    StatusBadge(text: L10n.t("缺少 {{text}}"), tone: .danger)
                }

                Spacer()

                if !hasPlaceholder {
                    Button(L10n.t("插入 {{text}}")) {
                        insertTextPlaceholder()
                    }
                }

                Button(L10n.t("恢复默认…")) {
                    confirmingReset = true
                }
                .disabled(isDefaultTemplate)
                .confirmationDialog(L10n.f("恢复默认的%@？", title), isPresented: $confirmingReset) {
                    Button(L10n.t("恢复")) { onReset() }
                } message: {
                    Text(L10n.t("你改过的内容会被替换，无法撤销。"))
                }
            }
        } header: {
            Text(title)
        }
    }

    private var editor: some View {
        TextEditor(text: $template)
            .font(AstryxFont.bodyMono)
            .scrollContentBackground(.hidden)
            .frame(height: PromptUITokens.editorHeight)
            .settingsWell(padding: Spacing.x2)
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

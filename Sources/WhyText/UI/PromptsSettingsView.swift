import SwiftUI

struct PromptsSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("翻译提示词") {
                TextEditor(text: $appModel.settingsStore.translatePromptTemplate)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 180)

                HStack {
                    Text("用 {{text}} 代表选中文本。")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("恢复默认") {
                        appModel.settingsStore.resetTranslatePromptTemplateToDefault()
                    }
                    .disabled(
                        appModel.settingsStore.translatePromptTemplate
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        == SettingsStore.defaultTranslatePromptTemplate
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
        }
    }
}

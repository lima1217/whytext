import SwiftUI
import WhyTextCore

struct MemorySettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var exportError: String?
    @State private var confirmingClear = false

    var body: some View {
        SettingsPage(.memory) {
            recordingSection
            exportSection
        }
    }

    private var recordingSection: some View {
        Section {
            Toggle(L10n.t("记录查过的词和段落"), isOn: $appModel.settingsStore.saveReadingMemory)
                .toggleStyle(.switch)
            CaptionText(text: L10n.f("已记录 %@ 条，只保存在这台 Mac 上。", String(appModel.readingMemory.recordCount)))
        }
    }

    private var exportSection: some View {
        Section {
            HStack {
                Button(L10n.t("导出到文件夹…")) {
                    exportError = nil
                    appModel.exportReadingMemory { error in
                        exportError = error
                    }
                }
                .disabled(appModel.readingMemory.recordCount == 0)

                Spacer()

                Button(L10n.t("清空阅读记忆…")) {
                    confirmingClear = true
                }
                .disabled(appModel.readingMemory.recordCount == 0)
            }

            if let exportError {
                CaptionText(text: exportError)
            }
        }
        .confirmationDialog(
            L10n.t("清空全部阅读记忆？"),
            isPresented: $confirmingClear
        ) {
            Button(L10n.t("清空"), role: .destructive) {
                appModel.clearReadingMemory()
            }
        } message: {
            Text(L10n.t("已导出的文件不受影响。"))
        }
    }
}

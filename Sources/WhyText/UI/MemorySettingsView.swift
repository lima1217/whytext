import SwiftUI
import WhyTextCore

struct MemorySettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var exportError: String?
    @State private var confirmingClear = false

    var body: some View {
        SettingsPage(.memory) {
            recordingSection
            glossarySection
            exportSection
        }
    }

    private var hasData: Bool {
        appModel.readingMemory.recordCount > 0 || !appModel.readingMemory.glossary.isEmpty
    }

    private var glossarySection: some View {
        Section(L10n.t("术语表")) {
            let entries = appModel.readingMemory.glossary
            if entries.isEmpty {
                CaptionText(text: L10n.t("在翻译结果上点星标，就能记下这个词的译法；以后翻译到它时会照用。"))
            } else {
                ForEach(entries) { entry in
                    GlossaryRow(entry: entry)
                }
                CaptionText(text: L10n.t("翻译时，用到的术语会随请求一起发给服务商。"))
            }
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
                .disabled(!hasData)

                Spacer()

                Button(L10n.t("清空阅读记忆…")) {
                    confirmingClear = true
                }
                .disabled(!hasData)
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

private struct GlossaryRow: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: GlossaryEntry

    var body: some View {
        HStack(spacing: Spacing.x2) {
            Text(entry.term)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 150, alignment: .leading)
                .help(entry.term)

            TextField(L10n.t("译法"), text: renderingBinding)
                .textFieldStyle(.roundedBorder)

            Text(TranslationLanguage(rawValue: entry.targetLanguage)?.displayName ?? entry.targetLanguage)
                .font(AstryxFont.captionM)
                .foregroundStyle(AstryxColor.textSecondary)
                .lineLimit(1)

            Button {
                appModel.readingMemory.removeGlossary(id: entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("从术语表移除"))
            .accessibilityLabel(L10n.f("从术语表移除 %@", entry.term))
        }
    }

    private var renderingBinding: Binding<String> {
        Binding(
            get: { entry.rendering },
            set: { rendering in
                var updated = entry
                updated.rendering = rendering
                appModel.readingMemory.upsertGlossary(updated)
            }
        )
    }
}

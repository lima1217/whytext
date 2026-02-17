import SwiftUI

struct HistorySettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("历史记录")
                    .font(.headline)

                Spacer()

                Button("清空") {
                    appModel.historyStore.removeAll()
                }
                .disabled(appModel.historyStore.entries.isEmpty)
            }

            List {
                ForEach(appModel.historyStore.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.action.displayName)
                                .font(.subheadline)
                            Text("· \(entry.providerName) \(entry.model)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }

                        Text(entry.inputText)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)

                        Text(entry.outputText)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}


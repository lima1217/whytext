import Combine
import Foundation

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private var cancellables = Set<AnyCancellable>()
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = (dir ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("WhyText", isDirectory: true)
        self.fileURL = base.appendingPathComponent("history.json")

        load()
        bindAutoSave()
    }

    func append(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 200 {
            entries = Array(entries.prefix(200))
        }
    }

    func removeAll() {
        entries = []
    }

    private func bindAutoSave() {
        $entries
            .dropFirst()
            .sink { [weak self] _ in self?.persist() }
            .store(in: &cancellables)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        self.entries = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort.
        }
    }
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var action: PanelAction
    var inputText: String
    var outputText: String
    var providerName: String
    var model: String

    init(
        id: UUID = UUID(),
        date: Date,
        action: PanelAction,
        inputText: String,
        outputText: String,
        providerName: String,
        model: String
    ) {
        self.id = id
        self.date = date
        self.action = action
        self.inputText = inputText
        self.outputText = outputText
        self.providerName = providerName
        self.model = model
    }
}


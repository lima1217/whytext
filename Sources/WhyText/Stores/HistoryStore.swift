import Foundation
import WhyTextCore

/// Everything besides the source text that shapes a result. Two requests with the
/// same key and source would get an equivalent answer, so the stored one is reused.
struct HistoryCacheKey: Codable, Equatable {
    var action: PanelAction
    var targetLanguage: TranslationLanguage
    var providerID: UUID
    var baseURL: String
    var model: String
    var apiMode: LLMAPIMode
    var template: String
    var maxInputCharacters: Int
    var splitLongInput: Bool
    /// The glossary constraints sent with the request, so editing the glossary
    /// asks again. Optional: entries saved before the glossary decode as nil.
    var glossaryHint: String?
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var key: HistoryCacheKey
    var sourceText: String
    var resultText: String
    /// Replayed when the user asks a follow-up on a restored entry.
    var conversation: [ConversationMessage]
}

/// Recent results, newest first, kept in Application Support so they survive relaunch.
/// Used from the main thread only, like `SettingsStore`.
final class HistoryStore: ObservableObject {
    static let capacity = 50

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL?

    init(fileURL: URL? = HistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        entries = load()
    }

    func lookup(key: HistoryCacheKey, sourceText: String) -> HistoryEntry? {
        entries.first { $0.key == key && $0.sourceText == sourceText }
    }

    func record(_ entry: HistoryEntry) {
        var list = RecentList(items: entries, capacity: Self.capacity)
        list.insert(entry) { $0.key == entry.key && $0.sourceText == entry.sourceText }
        entries = list.items
        save()
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
        save()
    }

    private func load() -> [HistoryEntry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoded = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
        return Array(decoded.prefix(Self.capacity))
    }

    private func save() {
        guard let fileURL else { return }
        do {
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // Best-effort: history is a convenience, not data the user asked to keep.
        }
    }

    /// `~/Library/Application Support/<bundle ID>/`, shared with `ReadingMemoryStore`.
    static func supportDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = Bundle.main.bundleIdentifier ?? "WhyText"
        return base.appendingPathComponent(folder, isDirectory: true)
    }

    private static func defaultFileURL() -> URL? {
        supportDirectory()?
            // Not "history.json": a removed earlier feature used that name, in a
            // different format, and its leftover file must not be overwritten.
            .appendingPathComponent("recent-results.json")
    }
}

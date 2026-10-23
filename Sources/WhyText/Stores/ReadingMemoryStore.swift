import Foundation
import WhyTextCore

/// Every finished lookup, kept so reading leaves something behind. Unlike
/// `HistoryStore` (a 50-entry cache), this only grows until the user clears it.
/// Used from the main thread; file IO runs on a serial background queue.
final class ReadingMemoryStore: ObservableObject {
    @Published private(set) var recordCount = 0

    private(set) var records: [LookupRecord] = [] {
        didSet { recordCount = records.count }
    }
    /// termKey → panel sessions that looked it up.
    private var termSessions: [String: Set<UUID>] = [:]
    /// Set by `clearAll()` so a load still in flight doesn't bring cleared records back.
    private var clearedWhileLoading = false

    private let fileURL: URL?
    private let queue = DispatchQueue(label: "whytext.reading-memory", qos: .utility)

    init(fileURL: URL? = ReadingMemoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        guard let fileURL else { return }
        // Read off the main thread: a year of lookups is megabytes of JSON.
        queue.async { [weak self] in
            let loaded = (try? Data(contentsOf: fileURL)).map(LookupLog.decode) ?? []
            DispatchQueue.main.async {
                guard let self, !self.clearedWhileLoading else { return }
                // Lookups appended while loading are newer than anything on disk.
                self.records = loaded + self.records
                self.termSessions = [:]
                self.records.forEach(self.index)
            }
        }
    }

    /// Panel sessions, including the current one, that looked up this term.
    func count(for termKey: String) -> Int {
        termSessions[termKey]?.count ?? 0
    }

    func append(_ record: LookupRecord) {
        records.append(record)
        index(record)
        guard let fileURL, let line = try? LookupLog.encodeLine(record) else { return }
        queue.async {
            Self.appendLine(line, to: fileURL)
        }
    }

    func clearAll() {
        clearedWhileLoading = true
        records = []
        termSessions = [:]
        guard let fileURL else { return }
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    enum ExportError: LocalizedError {
        case folderNotOurs(String)

        var errorDescription: String? {
            switch self {
            case .folderNotOurs(let name):
                L10n.f("「%@」已存在，且不是 WhyText 导出的文件夹。请换一个位置。", name)
            }
        }
    }

    /// Writes the Markdown export into `parent`, replacing an earlier WhyText export
    /// there but never a folder WhyText didn't create. Returns the export folder.
    func export(into parent: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let files = MemoryMarkdownExporter.render(records: records, exportedAt: Date())
        let folderName = MemoryMarkdownExporter.folderName
        queue.async {
            let result = Result { try Self.write(files, folderName: folderName, into: parent) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Private

    private func index(_ record: LookupRecord) {
        guard let key = record.termKey else { return }
        termSessions[key, default: []].insert(record.sessionID)
    }

    private static func appendLine(_ line: Data, to fileURL: URL) {
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try manager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try line.write(to: fileURL, options: [.atomic, .completeFileProtection])
            }
        } catch {
            // Best-effort: losing one lookup must never break a translation.
        }
    }

    /// Builds the export next to its destination, then swaps it in whole, so a
    /// failure never leaves a half-written folder.
    private static func write(_ files: [String: String], folderName: String, into parent: URL) throws -> URL {
        let manager = FileManager.default
        let destination = parent.appendingPathComponent(folderName, isDirectory: true)
        let marker = destination.appendingPathComponent(MemoryMarkdownExporter.markerFileName)
        let exists = manager.fileExists(atPath: destination.path)
        if exists, !manager.fileExists(atPath: marker.path) {
            throw ExportError.folderNotOurs(folderName)
        }

        let staging = parent.appendingPathComponent(".\(folderName).tmp", isDirectory: true)
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for (path, contents) in files {
                let fileURL = staging.appendingPathComponent(path)
                try manager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(contents.utf8).write(to: fileURL)
            }
            if exists {
                _ = try manager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: destination)
            }
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
        return destination
    }

    private static func defaultFileURL() -> URL? {
        HistoryStore.supportDirectory()?
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("lookups.jsonl")
    }
}

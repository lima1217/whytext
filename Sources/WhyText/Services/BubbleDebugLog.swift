import Foundation

// [DEBUG-BUBBLE] Temporary instrumentation for diagnosing the selection
// auto-popup chain. Remove this file once the bug is fixed.
enum BubbleDebugLog {
    private static let queue = DispatchQueue(label: "whytext.bubble.debug.log")

    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("WhyText.autopopup.log")
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) [DEBUG-BUBBLE] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

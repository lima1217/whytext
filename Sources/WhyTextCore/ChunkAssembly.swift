import Foundation

/// Joins per-chunk outputs that may finish out of order into the text to show.
///
/// Only the leading run of chunks is visible: every finished chunk up to the first
/// unfinished one, plus that chunk's partial text. Later chunks that finish early
/// stay hidden until the reader reaches them, so text never appears mid-document.
public struct ChunkAssembly: Equatable {
    public private(set) var parts: [String]
    public private(set) var finished: [Bool]
    public let separator: String

    public init(count: Int, separator: String = "\n\n") {
        self.parts = Array(repeating: "", count: count)
        self.finished = Array(repeating: false, count: count)
        self.separator = separator
    }

    public mutating func setPartial(_ text: String, at index: Int) {
        parts[index] = text
    }

    public mutating func finish(_ text: String, at index: Int) {
        parts[index] = text
        finished[index] = true
    }

    public var isComplete: Bool {
        finished.allSatisfy { $0 }
    }

    public var visibleText: String {
        var visible: [String] = []
        for (part, done) in zip(parts, finished) {
            visible.append(part)
            if !done { break }
        }
        return visible.joined(separator: separator)
    }

    public var fullText: String {
        parts.joined(separator: separator)
    }
}

/// Most-recent-first list with a fixed capacity; re-inserting a matching element
/// moves it to the front instead of duplicating it.
public struct RecentList<Element> {
    public private(set) var items: [Element]
    public let capacity: Int

    public init(items: [Element] = [], capacity: Int) {
        self.capacity = max(capacity, 0)
        self.items = Array(items.prefix(self.capacity))
    }

    public mutating func insert(_ element: Element, replacing matches: (Element) -> Bool) {
        items.removeAll(where: matches)
        items.insert(element, at: 0)
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
    }

    public mutating func removeAll() {
        items.removeAll()
    }
}

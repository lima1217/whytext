import Foundation

/// Turns recognized text lines back into paragraphs, so a screenshot of wrapped
/// prose reads as prose instead of one paragraph per visual line.
public enum OCRTextLayout {
    /// One recognized line. Coordinates are normalized to the image (0…1) with the
    /// origin at the top-left, so `top < bottom`.
    public struct Line: Equatable {
        public var text: String
        public var minX: Double
        public var top: Double
        public var maxX: Double
        public var bottom: Double

        public init(text: String, minX: Double, top: Double, maxX: Double, bottom: Double) {
            self.text = text
            self.minX = minX
            self.top = top
            self.maxX = maxX
            self.bottom = bottom
        }

        var height: Double { bottom - top }
        var width: Double { maxX - minX }
    }

    public static func join(_ lines: [Line]) -> String {
        let rows = groupIntoRows(lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        guard let first = rows.first else { return "" }

        let heights = rows.map(\.height).sorted()
        let typicalHeight = heights[heights.count / 2]
        let widestRow = rows.map(\.width).max() ?? 0

        var output = first.text.trimmingCharacters(in: .whitespaces)
        for (previous, row) in zip(rows, rows.dropFirst()) {
            let text = row.text.trimmingCharacters(in: .whitespaces)
            let gap = row.top - previous.bottom

            if gap > typicalHeight * 0.8 {
                // A blank line's worth of space: new paragraph.
                output += "\n\n" + text
            } else if previous.width < widestRow * 0.5 {
                // A short line that isn't the end of a paragraph is a heading or list item.
                output += "\n" + text
            } else {
                output = joinWrapped(output, text)
            }
        }
        return output
    }

    /// Lines whose vertical extents mostly overlap sit on the same row (e.g. a label
    /// and its value); merge them left to right.
    private static func groupIntoRows(_ lines: [Line]) -> [Line] {
        let sorted = lines.sorted { $0.top < $1.top }
        var rows: [[Line]] = []

        for line in sorted {
            if let lastRow = rows.last, let anchor = lastRow.first {
                let overlap = min(anchor.bottom, line.bottom) - max(anchor.top, line.top)
                if overlap > min(anchor.height, line.height) * 0.5 {
                    rows[rows.count - 1].append(line)
                    continue
                }
            }
            rows.append([line])
        }

        return rows.map { row in
            let ordered = row.sorted { $0.minX < $1.minX }
            return Line(
                text: ordered.map(\.text).joined(separator: " "),
                minX: ordered.map(\.minX).min() ?? 0,
                top: ordered.map(\.top).min() ?? 0,
                maxX: ordered.map(\.maxX).max() ?? 0,
                bottom: ordered.map(\.bottom).max() ?? 0
            )
        }
    }

    /// Joins a soft-wrapped line: no space between CJK characters, a space between
    /// words, and a trailing hyphen rejoins a split word.
    private static func joinWrapped(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }

        if last == "-", head.dropLast().last?.isLetter == true, first.isLowercase {
            return String(head.dropLast()) + tail
        }
        if isCJK(last) || isCJK(first) {
            return head + tail
        }
        return head + " " + tail
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F, // CJK punctuation
                 0x3040...0x30FF, // kana
                 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, // han
                 0xAC00...0xD7AF, // hangul
                 0xFF00...0xFFEF: // full-width forms
                return true
            default:
                return false
            }
        }
    }
}

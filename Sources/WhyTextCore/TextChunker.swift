import Foundation

public enum TextChunker {
    public struct Result: Equatable {
        public var chunks: [String]
        public var wasTruncated: Bool

        public init(chunks: [String], wasTruncated: Bool) {
            self.chunks = chunks
            self.wasTruncated = wasTruncated
        }
    }

    public static func chunk(text: String, maxCharacters: Int, splitLongInput: Bool) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return Result(chunks: [trimmed], wasTruncated: false)
        }

        // Unlimited or under the budget: one request preserves structure via the prompt hint.
        guard maxCharacters > 0 else {
            return Result(chunks: [trimmed], wasTruncated: false)
        }

        if trimmed.count <= maxCharacters {
            return Result(chunks: [trimmed], wasTruncated: false)
        }

        if !splitLongInput {
            return Result(chunks: [String(trimmed.prefix(maxCharacters))], wasTruncated: true)
        }

        let paragraphs = splitIntoParagraphs(trimmed)
        let separator = paragraphSeparator(in: trimmed)
        var chunks = packIntoChunks(
            paragraphs: paragraphs,
            separator: separator,
            maxCharacters: maxCharacters
        )

        if chunks.count > 12 {
            chunks = Array(chunks.prefix(12))
        }

        if chunks.isEmpty {
            return Result(chunks: [String(trimmed.prefix(maxCharacters))], wasTruncated: false)
        }

        return Result(chunks: chunks, wasTruncated: false)
    }

    private static func paragraphSeparator(in text: String) -> String {
        if text.contains("\n\n") {
            return "\n\n"
        }
        if text.contains("\n") {
            return "\n"
        }
        return "\n\n"
    }

    private static func splitIntoParagraphs(_ text: String) -> [String] {
        if text.contains("\n\n") {
            var paragraphs: [String] = []
            var current: [String] = []

            for line in text.components(separatedBy: .newlines) {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !current.isEmpty {
                        let paragraph = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !paragraph.isEmpty {
                            paragraphs.append(paragraph)
                        }
                        current.removeAll(keepingCapacity: true)
                    }
                } else {
                    current.append(line)
                }
            }

            if !current.isEmpty {
                let paragraph = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraph.isEmpty {
                    paragraphs.append(paragraph)
                }
            }

            return paragraphs.isEmpty ? [text] : paragraphs
        }

        if text.contains("\n") {
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.isEmpty ? [text] : lines
        }

        return [text]
    }

    /// Pack paragraphs into as few capacity-bounded chunks as possible.
    private static func packIntoChunks(
        paragraphs: [String],
        separator: String,
        maxCharacters: Int
    ) -> [String] {
        var chunks: [String] = []
        var current = ""

        func flushCurrent() {
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                chunks.append(piece)
            }
            current = ""
        }

        for paragraph in paragraphs {
            if chunks.count >= 12 {
                return chunks
            }

            if paragraph.count > maxCharacters {
                flushCurrent()
                appendHardCutParts(
                    of: paragraph,
                    maxCharacters: maxCharacters,
                    into: &chunks
                )
                continue
            }

            if current.isEmpty {
                current = paragraph
                continue
            }

            let candidate = current + separator + paragraph
            if candidate.count <= maxCharacters {
                current = candidate
            } else {
                flushCurrent()
                if chunks.count >= 12 {
                    return chunks
                }
                current = paragraph
            }
        }

        flushCurrent()
        return chunks
    }

    private static func appendHardCutParts(
        of text: String,
        maxCharacters: Int,
        into chunks: inout [String]
    ) {
        var remaining = text
        while !remaining.isEmpty {
            if chunks.count >= 12 {
                return
            }

            if remaining.count <= maxCharacters {
                let last = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !last.isEmpty {
                    chunks.append(last)
                }
                return
            }

            let hardCut = remaining.index(remaining.startIndex, offsetBy: maxCharacters)
            let head = remaining[..<hardCut]
            let boundary = head.lastIndex(where: { $0 == "\n" || $0 == " " || $0 == "\t" })
            let cut = boundary ?? hardCut

            let part = String(remaining[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty {
                chunks.append(part)
            }

            remaining = String(remaining[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

import Foundation

enum TextChunker {
    struct Result: Equatable {
        var chunks: [String]
        var wasTruncated: Bool
    }

    static func chunk(text: String, maxCharacters: Int, splitLongInput: Bool) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = splitIntoParagraphs(trimmed)

        guard maxCharacters > 0 else {
            return Result(chunks: paragraphs.isEmpty ? [trimmed] : paragraphs, wasTruncated: false)
        }

        if !splitLongInput {
            if trimmed.count <= maxCharacters {
                return Result(chunks: paragraphs.isEmpty ? [trimmed] : paragraphs, wasTruncated: false)
            }
            return Result(chunks: [String(trimmed.prefix(maxCharacters))], wasTruncated: true)
        }

        if trimmed.count <= maxCharacters {
            if paragraphs.count > 1 {
                return Result(chunks: paragraphs, wasTruncated: false)
            }
            return Result(chunks: [trimmed], wasTruncated: false)
        }

        var chunks = splitParagraphsIntoChunks(
            paragraphs: paragraphs,
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

    private static func splitParagraphsIntoChunks(paragraphs: [String], maxCharacters: Int) -> [String] {
        var chunks: [String] = []

        for paragraph in paragraphs {
            if paragraph.count <= maxCharacters {
                chunks.append(paragraph)
                continue
            }

            var remaining = paragraph
            while !remaining.isEmpty {
                if remaining.count <= maxCharacters {
                    let last = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !last.isEmpty {
                        chunks.append(last)
                    }
                    break
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

                if chunks.count >= 12 {
                    return chunks
                }
            }
        }

        return chunks
    }
}

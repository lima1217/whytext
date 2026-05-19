import Foundation

public enum CJKLatinSpacer {
    public static func apply(toPlainText text: String) -> String {
        guard !text.isEmpty else { return text }

        var output = ""
        output.reserveCapacity(text.count)

        var previous: Character?
        var isInlineCode = false
        var isFencedCode = false
        var lineBacktickCount = 0

        for character in text {
            if character == "\n" {
                previous = nil
                lineBacktickCount = 0
                output.append(character)
                continue
            }

            if character == "`" {
                lineBacktickCount += 1
                if lineBacktickCount >= 3 {
                    isFencedCode.toggle()
                    isInlineCode = false
                } else if !isFencedCode {
                    isInlineCode.toggle()
                }
                output.append(character)
                previous = character
                continue
            }

            if !isInlineCode,
               !isFencedCode,
               let previous,
               !previous.isWhitespace,
               !character.isWhitespace,
               needsSpaceBetween(previous, character) {
                output.append(" ")
            }

            output.append(character)
            previous = character
        }

        return output
    }

    public static func needsSpaceBetween(_ lhs: Character, _ rhs: Character) -> Bool {
        (isCJK(lhs) && isLatinOrNumber(rhs)) || (isLatinOrNumber(lhs) && isCJK(rhs))
    }

    private static func isLatinOrNumber(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && !isCJK(scalar)
        }
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: isCJK)
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xAC00...0xD7AF,
             0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}

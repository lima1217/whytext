import AppKit
import Foundation

struct KeyboardShortcut: Codable, Hashable {
    var keyCode: UInt32
    var modifierFlagsRaw: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
    }

    var displayString: String {
        var parts: [String] = []
        let flags = modifierFlags

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    static let defaultShortcut = KeyboardShortcut(
        keyCode: 49, // Space
        modifierFlagsRaw: NSEvent.ModifierFlags.option.rawValue
    )
}

private func keyName(for keyCode: UInt32) -> String {
    switch keyCode {
    case 49:
        return "Space"
    case 36:
        return "Return"
    case 48:
        return "Tab"
    case 53:
        return "Esc"
    default:
        break
    }

    let map: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: "."
    ]

    return map[keyCode] ?? "#\(keyCode)"
}


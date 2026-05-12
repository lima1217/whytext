import AppKit
import Carbon.HIToolbox
import Foundation

final class ClipboardSelectionFallbackService {
    private struct PasteboardSnapshot {
        var typeData: [NSPasteboard.PasteboardType: Data]
    }

    func readSelectedTextViaCopy(timeout: TimeInterval = 0.35) async -> String? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }

        let pasteboard = NSPasteboard.general
        let snapshot = capturePasteboardSnapshot(from: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        guard postCommandC(using: source) else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != initialChangeCount {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

        restorePasteboardSnapshot(snapshot, to: pasteboard)

        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func postCommandC(using source: CGEventSource) -> Bool {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func capturePasteboardSnapshot(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        // Avoid `pasteboardItems`: on newer macOS versions it can raise ObjC exceptions
        // when the pasteboard mutates while being enumerated.
        var typeData: [NSPasteboard.PasteboardType: Data] = [:]

        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                typeData[type] = data
            }
        }

        return PasteboardSnapshot(typeData: typeData)
    }

    private func restorePasteboardSnapshot(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        guard !snapshot.typeData.isEmpty else {
            return
        }

        let item = NSPasteboardItem()
        for (type, data) in snapshot.typeData {
            item.setData(data, forType: type)
        }

        pasteboard.writeObjects([item])
    }
}

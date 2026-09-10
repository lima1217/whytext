import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

final class ClipboardSelectionFallbackService {
    private struct PasteboardSnapshot {
        var typeData: [NSPasteboard.PasteboardType: Data]
    }

    @MainActor
    func readSelectedTextViaCopy(timeout: TimeInterval = 0.35) async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = capturePasteboardSnapshot(from: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        // Prefer AX "Edit → Copy" — it does not synthesize ⌘C, so apps usually
        // stay quiet (no system alert beep). Fall back to a key event only if needed.
        let viaMenu = performCopyViaMenuBar()
        let triggered = viaMenu || postCommandC()
        BubbleDebugLog.log("clipboard copy viaMenu=\(viaMenu) triggered=\(triggered)")
        guard triggered else { return nil }

        defer {
            restorePasteboardSnapshot(snapshot, to: pasteboard)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var didChange = false
        while Date() < deadline {
            if pasteboard.changeCount != initialChangeCount {
                didChange = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        guard didChange else { return nil }

        let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// Presses the frontmost app's Copy menu item through Accessibility.
    private func performCopyViaMenuBar() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let menuBar = copyElement(kAXMenuBarAttribute as CFString, from: appElement),
              let menus = copyChildren(from: menuBar) else {
            return false
        }

        let editTitles: Set<String> = ["Edit", "编辑"]
        let copyTitles: Set<String> = ["Copy", "拷贝", "复制"]

        for menu in menus {
            let menuTitle = copyString(kAXTitleAttribute as CFString, from: menu) ?? ""
            let matchesEdit = editTitles.contains(menuTitle)

            // Some apps expose Copy on the first level; most nest it under Edit.
            if let copyItem = findMenuItem(titled: copyTitles, in: menu, depth: 0, maxDepth: matchesEdit ? 3 : 1) {
                let error = AXUIElementPerformAction(copyItem, kAXPressAction as CFString)
                return error == .success
            }
        }

        return false
    }

    private func findMenuItem(
        titled titles: Set<String>,
        in root: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) -> AXUIElement? {
        if depth > maxDepth { return nil }

        if let title = copyString(kAXTitleAttribute as CFString, from: root),
           titles.contains(title) {
            // Prefer enabled items; still try press if enabled flag is unavailable.
            if copyBool(kAXEnabledAttribute as CFString, from: root) != false {
                return root
            }
        }

        guard let children = copyChildren(from: root) else { return nil }
        for child in children {
            if let match = findMenuItem(titled: titles, in: child, depth: depth + 1, maxDepth: maxDepth) {
                return match
            }
        }
        return nil
    }

    private func postCommandC() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    private func copyElement(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyChildren(from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard error == .success, let value else { return nil }
        guard CFGetTypeID(value) == CFArrayGetTypeID() else { return nil }

        let array = unsafeBitCast(value, to: CFArray.self)
        let count = CFArrayGetCount(array)
        var result: [AXUIElement] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
            let candidate = unsafeBitCast(raw, to: CFTypeRef.self)
            guard CFGetTypeID(candidate) == AXUIElementGetTypeID() else { continue }
            result.append(unsafeBitCast(candidate, to: AXUIElement.self))
        }
        return result
    }

    private func copyString(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private func copyBool(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? Bool
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

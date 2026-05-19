import AppKit
import ApplicationServices
import Foundation

struct SelectionDiagnostics: Equatable {
    var report: String
    var selectedText: String?
}

struct SelectedTextResult: Equatable {
    var text: String
    var anchorRect: CGRect?
}

final class AccessibilitySelectionService {
    enum Status: Equatable {
        case trusted
        case notTrusted
    }

    private let markerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
    private let markerStringAttribute = "AXStringForTextMarkerRange" as CFString
    private let boundsForRangeAttribute = "AXBoundsForRange" as CFString
    private let boundsForMarkerRangeAttribute = "AXBoundsForTextMarkerRange" as CFString
    private let descendantSearchAttributes: [CFString] = [
        "AXSelectedChildren" as CFString,
        "AXSelectedRows" as CFString,
        "AXSelectedCells" as CFString,
        "AXVisibleChildren" as CFString,
        "AXContents" as CFString,
        kAXChildrenAttribute as CFString,
    ]
    private let chromiumAncestorAttributes: [CFString] = [
        "AXHighestEditableAncestor" as CFString,
        "AXEditableAncestor" as CFString,
        "AXFocusableAncestor" as CFString,
    ]

    func status() -> Status {
        isTrusted(prompt: false) ? .trusted : .notTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestPermissionPrompt() {
        let now = Date()
        if let last = Self.lastPromptAt, now.timeIntervalSince(last) < 30 {
            return
        }
        Self.lastPromptAt = now

        _ = isTrusted(prompt: true)
    }

    private static var lastPromptAt: Date?

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    func collectDiagnostics() -> SelectionDiagnostics {
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        lines.append("time: \(formatter.string(from: Date()))")
        lines.append("accessibilityTrusted: \(status() == .trusted)")

        if let app = NSWorkspace.shared.frontmostApplication {
            lines.append("frontmostApp: \(app.localizedName ?? "(unknown)")")
            lines.append("frontmostBundleID: \(app.bundleIdentifier ?? "(unknown)")")
            lines.append("frontmostPID: \(app.processIdentifier)")
        } else {
            lines.append("frontmostApp: (none)")
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let focusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: systemWide) {
            lines.append(contentsOf: describeElement(focusedElement, prefix: "focusedElement"))
        } else {
            lines.append("focusedElement: unavailable")
        }

        if let focusedApp = copyElementAttribute(kAXFocusedApplicationAttribute as CFString, from: systemWide) {
            lines.append("focusedApplication: available")
            if let appFocusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: focusedApp) {
                lines.append(contentsOf: describeElement(appFocusedElement, prefix: "focusedApp.focusedElement"))
            } else {
                lines.append("focusedApp.focusedElement: unavailable")
            }
        } else {
            lines.append("focusedApplication: unavailable")
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            let frontmostAppElement = AXUIElementCreateApplication(app.processIdentifier)
            if let appFocusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: frontmostAppElement) {
                lines.append(contentsOf: describeElement(appFocusedElement, prefix: "frontmostApp.focusedElement"))
            } else {
                lines.append("frontmostApp.focusedElement: unavailable")
            }
        }

        var selectedText: String?
        do {
            let result = try getSelectedTextResult()
            selectedText = result.text
            lines.append("getSelectedText: success")
            lines.append("selectedLength: \(result.text.count)")
            lines.append("selectedPreview: \(preview(result.text))")
            if let anchorRect = result.anchorRect {
                lines.append("selectedAnchorRect: \(anchorRect.debugDescription)")
            } else {
                lines.append("selectedAnchorRect: unavailable")
            }
        } catch {
            lines.append("getSelectedText: failed")
            lines.append("error: \(error.localizedDescription)")
        }

        return SelectionDiagnostics(report: lines.joined(separator: "\n"), selectedText: selectedText)
    }

    func getSelectedText() throws -> String {
        try getSelectedTextResult().text
    }

    func getSelectedTextResult() throws -> SelectedTextResult {
        guard status() == .trusted else {
            throw SelectionError.notTrusted
        }

        let systemWide = AXUIElementCreateSystemWide()

        if let result = try selectedText(from: systemWide) {
            return result
        }

        throw SelectionError.noSelection
    }

    private func selectedText(from systemWide: AXUIElement) throws -> SelectedTextResult? {
        var visited = Set<Int>()
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let element = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: systemWide) {
            if isChromiumBundleID(frontmostBundleID),
               let result = try selectedTextInChromiumContext(startingAt: element, visited: &visited) {
                return result
            }

            if let result = try selectedText(near: element, ancestorDepth: 4, descendantDepth: 6, visited: &visited) {
                return result
            }
        }

        if let appElement = copyElementAttribute(kAXFocusedApplicationAttribute as CFString, from: systemWide) {
            if isChromiumBundleID(frontmostBundleID),
               let result = try selectedText(fromChromiumAppElement: appElement, visited: &visited) {
                return result
            }

            if let result = try selectedText(fromAppElement: appElement, visited: &visited) {
                return result
            }
        }

        // Some apps may fail AXFocusedApplication lookup from the system-wide element.
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

            if isChromiumBundleID(frontmostApp.bundleIdentifier),
               let result = try selectedText(fromChromiumAppElement: appElement, visited: &visited) {
                return result
            }

            if let result = try selectedText(fromAppElement: appElement, visited: &visited) {
                return result
            }
        }

        return nil
    }

    private func selectedText(near element: AXUIElement, ancestorDepth: Int, descendantDepth: Int, visited: inout Set<Int>) throws -> SelectedTextResult? {
        if let result = try selectedText(in: element) {
            return result
        }

        if let result = try selectedTextAlongAncestorChain(startingAt: element, maxDepth: ancestorDepth, visited: &visited) {
            return result
        }

        if let result = try selectedTextRecursively(in: element, depth: 0, maxDepth: descendantDepth, visited: &visited) {
            return result
        }

        return nil
    }

    private func selectedText(in element: AXUIElement) throws -> SelectedTextResult? {
        if let text = nonEmptyTrimmed(copyStringAttribute(kAXSelectedTextAttribute as CFString, from: element)) {
            return SelectedTextResult(text: text, anchorRect: selectedBounds(in: element))
        }

        if let selectedRangeValue = copyAXValueAttribute(kAXSelectedTextRangeAttribute as CFString, from: element),
           let text = selectedText(for: selectedRangeValue, in: element) {
            return SelectedTextResult(text: text, anchorRect: selectedBounds(for: selectedRangeValue, in: element))
        }

        if let markerSelection = selectedTextFromMarkerRange(in: element) {
            return markerSelection
        }

        return nil
    }

    private func selectedText(for selectedRangeValue: AXValue, in element: AXUIElement) -> String? {
        if let text = stringForSelectedRange(in: element, selectedRangeValue: selectedRangeValue) {
            return text
        }

        guard let range = extractCFRange(from: selectedRangeValue),
              range.location != kCFNotFound,
              range.length > 0 else {
            return nil
        }

        if let value = copyStringAttribute(kAXValueAttribute as CFString, from: element),
           let sliced = substring(value, utf16Range: range),
           let text = nonEmptyTrimmed(sliced) {
            return text
        }

        if let attributedValue = copyAttributedStringAttribute("AXAttributedValue" as CFString, from: element),
           let sliced = substring(attributedValue.string, utf16Range: range),
           let text = nonEmptyTrimmed(sliced) {
            return text
        }

        return nil
    }

    private func selectedTextFromMarkerRange(in element: AXUIElement) -> SelectedTextResult? {
        var markerRange: CFTypeRef?
        let markerError = AXUIElementCopyAttributeValue(element, markerRangeAttribute, &markerRange)
        guard markerError == .success, let markerRange else {
            return nil
        }

        var markerText: CFTypeRef?
        let markerTextError = AXUIElementCopyParameterizedAttributeValue(
            element,
            markerStringAttribute,
            markerRange,
            &markerText
        )

        guard markerTextError == .success, let markerText = markerText as? String else {
            return nil
        }

        guard let text = nonEmptyTrimmed(markerText) else {
            return nil
        }

        return SelectedTextResult(text: text, anchorRect: selectedBounds(forMarkerRange: markerRange, in: element))
    }

    private func selectedBounds(in element: AXUIElement) -> CGRect? {
        guard let selectedRangeValue = copyAXValueAttribute(kAXSelectedTextRangeAttribute as CFString, from: element) else {
            return nil
        }
        return selectedBounds(for: selectedRangeValue, in: element)
    }

    private func selectedBounds(for selectedRangeValue: AXValue, in element: AXUIElement) -> CGRect? {
        var boundsValue: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            boundsForRangeAttribute,
            selectedRangeValue,
            &boundsValue
        )

        guard error == .success, let boundsValue else {
            return nil
        }

        guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(boundsValue, to: AXValue.self)
        return rect(from: axValue)
    }

    private func selectedBounds(forMarkerRange markerRange: CFTypeRef, in element: AXUIElement) -> CGRect? {
        var boundsValue: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            boundsForMarkerRangeAttribute,
            markerRange,
            &boundsValue
        )

        guard error == .success, let boundsValue else {
            return nil
        }

        guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(boundsValue, to: AXValue.self)
        return rect(from: axValue)
    }

    private func rect(from axValue: AXValue) -> CGRect? {
        let type = AXValueGetType(axValue)
        var rect = CGRect.zero

        if type == AXValueType(rawValue: kAXValueCGRectType),
           AXValueGetValue(axValue, type, &rect),
           rect.width > 0,
           rect.height > 0 {
            return rect
        }

        return nil
    }

    private func stringForSelectedRange(in element: AXUIElement, selectedRangeValue: AXValue) -> String? {
        var rangeString: CFTypeRef?
        let paramError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &rangeString
        )

        guard paramError == .success, let rangeString = rangeString as? String else {
            return nil
        }

        return nonEmptyTrimmed(rangeString)
    }

    private func selectedText(fromAppElement appElement: AXUIElement, visited: inout Set<Int>) throws -> SelectedTextResult? {
        if let appFocusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement),
           let result = try selectedText(near: appFocusedElement, ancestorDepth: 4, descendantDepth: 6, visited: &visited) {
            return result
        }

        if let focusedWindow = copyElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement),
           let result = try selectedText(near: focusedWindow, ancestorDepth: 2, descendantDepth: 8, visited: &visited) {
            return result
        }

        if let mainWindow = copyElementAttribute(kAXMainWindowAttribute as CFString, from: appElement),
           let result = try selectedText(near: mainWindow, ancestorDepth: 2, descendantDepth: 8, visited: &visited) {
            return result
        }

        if let windows = copyElementArrayAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            for window in windows {
                if let result = try selectedText(near: window, ancestorDepth: 1, descendantDepth: 6, visited: &visited) {
                    return result
                }
            }
        }

        return nil
    }

    private func selectedTextInChromiumContext(startingAt element: AXUIElement, visited: inout Set<Int>) throws -> SelectedTextResult? {
        if let result = try selectedText(in: element) {
            return result
        }

        for attribute in chromiumAncestorAttributes {
            if let ancestor = copyElementAttribute(attribute, from: element),
               let result = try selectedText(near: ancestor, ancestorDepth: 3, descendantDepth: 8, visited: &visited) {
                return result
            }
        }

        if let webArea = findNearestAncestor(withRole: "AXWebArea", startingAt: element, maxDepth: 8),
           let result = try selectedText(near: webArea, ancestorDepth: 1, descendantDepth: 10, visited: &visited) {
            return result
        }

        for webArea in findDescendants(withRoles: ["AXWebArea"], from: element, maxDepth: 10, limit: 8) {
            if let result = try selectedText(near: webArea, ancestorDepth: 1, descendantDepth: 10, visited: &visited) {
                return result
            }
        }

        return try selectedText(near: element, ancestorDepth: 5, descendantDepth: 10, visited: &visited)
    }

    private func selectedText(fromChromiumAppElement appElement: AXUIElement, visited: inout Set<Int>) throws -> SelectedTextResult? {
        if let appFocusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement),
           let result = try selectedTextInChromiumContext(startingAt: appFocusedElement, visited: &visited) {
            return result
        }

        let candidateWindows = [
            copyElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement),
            copyElementAttribute(kAXMainWindowAttribute as CFString, from: appElement),
        ].compactMap { $0 }

        for window in candidateWindows {
            if let result = try selectedTextFromChromiumWindow(window, visited: &visited) {
                return result
            }
        }

        if let windows = copyElementArrayAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            for window in windows {
                if let result = try selectedTextFromChromiumWindow(window, visited: &visited) {
                    return result
                }
            }
        }

        return try selectedText(fromAppElement: appElement, visited: &visited)
    }

    private func selectedTextFromChromiumWindow(_ window: AXUIElement, visited: inout Set<Int>) throws -> SelectedTextResult? {
        for webArea in findDescendants(withRoles: ["AXWebArea"], from: window, maxDepth: 12, limit: 12) {
            if let result = try selectedText(near: webArea, ancestorDepth: 1, descendantDepth: 10, visited: &visited) {
                return result
            }
        }

        return try selectedText(near: window, ancestorDepth: 2, descendantDepth: 10, visited: &visited)
    }

    private func selectedTextAlongAncestorChain(startingAt element: AXUIElement, maxDepth: Int, visited: inout Set<Int>) throws -> SelectedTextResult? {
        var current = element

        for _ in 0..<maxDepth {
            guard let parent = copyElementAttribute(kAXParentAttribute as CFString, from: current) else {
                return nil
            }

            let key = elementKey(parent)
            if visited.contains(key) {
                return nil
            }
            visited.insert(key)

            if let result = try selectedText(in: parent) {
                return result
            }

            current = parent
        }

        return nil
    }

    private func selectedTextRecursively(in element: AXUIElement, depth: Int, maxDepth: Int, visited: inout Set<Int>) throws -> SelectedTextResult? {
        if depth >= maxDepth {
            return nil
        }

        let key = elementKey(element)
        if visited.contains(key) {
            return nil
        }
        visited.insert(key)

        let relatedElements = copyRelatedElements(from: element)
        guard !relatedElements.isEmpty else {
            return nil
        }

        for related in relatedElements {
            if let result = try selectedText(in: related) {
                return result
            }
        }

        for related in relatedElements {
            if let result = try selectedTextRecursively(in: related, depth: depth + 1, maxDepth: maxDepth, visited: &visited) {
                return result
            }
        }

        return nil
    }

    private func describeElement(_ element: AXUIElement, prefix: String) -> [String] {
        let names = copyAttributeNames(from: element)
        let role = copyStringAttribute(kAXRoleAttribute as CFString, from: element) ?? "(none)"
        let subrole = copyStringAttribute(kAXSubroleAttribute as CFString, from: element) ?? "(none)"
        let title = copyStringAttribute(kAXTitleAttribute as CFString, from: element) ?? "(none)"
        let valuePreview = copyStringAttribute(kAXValueAttribute as CFString, from: element).map { preview($0) } ?? "(none)"

        var lines: [String] = []
        lines.append("\(prefix).role: \(role)")
        lines.append("\(prefix).subrole: \(subrole)")
        lines.append("\(prefix).title: \(preview(title))")
        lines.append("\(prefix).valuePreview: \(valuePreview)")
        lines.append("\(prefix).hasAXSelectedText: \(names.contains(kAXSelectedTextAttribute as String))")
        lines.append("\(prefix).hasAXSelectedTextRange: \(names.contains(kAXSelectedTextRangeAttribute as String))")
        lines.append("\(prefix).hasAXSelectedTextMarkerRange: \(names.contains("AXSelectedTextMarkerRange"))")
        lines.append("\(prefix).hasAXValue: \(names.contains(kAXValueAttribute as String))")
        lines.append("\(prefix).hasAXParent: \(names.contains(kAXParentAttribute as String))")
        lines.append("\(prefix).relatedElementCount: \(copyRelatedElements(from: element).count)")
        return lines
    }

    private func copyAttributeNames(from element: AXUIElement) -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyAttributeNames(element, &names)
        guard error == .success, let array = names as? [String] else {
            return []
        }
        return array
    }

    private func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyElementArrayAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }

        let array = unsafeBitCast(value, to: CFArray.self)
        let count = CFArrayGetCount(array)
        if count == 0 {
            return []
        }

        var result: [AXUIElement] = []
        result.reserveCapacity(count)

        for index in 0..<count {
            guard let rawValue = CFArrayGetValueAtIndex(array, index) else { continue }
            let candidate = unsafeBitCast(rawValue, to: CFTypeRef.self)
            guard CFGetTypeID(candidate) == AXUIElementGetTypeID() else { continue }
            result.append(unsafeBitCast(candidate, to: AXUIElement.self))
        }

        return result
    }

    private func copyRelatedElements(from element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var seen = Set<Int>()

        for attribute in descendantSearchAttributes {
            for related in copyElementArrayAttribute(attribute, from: element) ?? [] {
                let key = elementKey(related)
                if seen.insert(key).inserted {
                    result.append(related)
                }
            }
        }

        return result
    }

    private func findNearestAncestor(withRole targetRole: String, startingAt element: AXUIElement, maxDepth: Int) -> AXUIElement? {
        var current = element

        for _ in 0..<maxDepth {
            guard let parent = copyElementAttribute(kAXParentAttribute as CFString, from: current) else {
                return nil
            }

            if copyStringAttribute(kAXRoleAttribute as CFString, from: parent) == targetRole {
                return parent
            }

            current = parent
        }

        return nil
    }

    private func findDescendants(withRoles roles: Set<String>, from root: AXUIElement, maxDepth: Int, limit: Int) -> [AXUIElement] {
        guard maxDepth > 0, limit > 0 else { return [] }

        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var seen = Set<Int>([elementKey(root)])
        var matches: [AXUIElement] = []

        while index < queue.count, matches.count < limit {
            let current = queue[index]
            index += 1

            if current.depth >= maxDepth {
                continue
            }

            for child in copyRelatedElements(from: current.element) {
                let key = elementKey(child)
                guard seen.insert(key).inserted else { continue }

                let depth = current.depth + 1
                if let role = copyStringAttribute(kAXRoleAttribute as CFString, from: child), roles.contains(role) {
                    matches.append(child)
                    if matches.count >= limit {
                        break
                    }
                }

                if depth < maxDepth {
                    queue.append((child, depth))
                }
            }
        }

        return matches
    }

    private func copyAXValueAttribute(_ attribute: CFString, from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        return unsafeBitCast(value, to: AXValue.self)
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private func copyAttributedStringAttribute(_ attribute: CFString, from element: AXUIElement) -> NSAttributedString? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? NSAttributedString
    }

    private func extractCFRange(from value: AXValue) -> CFRange? {
        let type = AXValueGetType(value)
        guard type == AXValueType(rawValue: kAXValueCFRangeType) else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, type, &range) else {
            return nil
        }

        return range
    }

    private func substring(_ text: String, utf16Range: CFRange) -> String? {
        guard utf16Range.location != kCFNotFound,
              utf16Range.location >= 0,
              utf16Range.length > 0 else {
            return nil
        }

        let nsText = text as NSString
        let end = utf16Range.location + utf16Range.length
        guard end <= nsText.length else {
            return nil
        }

        return nsText.substring(with: NSRange(location: utf16Range.location, length: utf16Range.length))
    }

    private func nonEmptyTrimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isChromiumBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }

        return bundleID == "com.google.Chrome"
            || bundleID == "com.google.Chrome.beta"
            || bundleID == "com.google.Chrome.canary"
            || bundleID == "com.google.Chrome.dev"
            || bundleID == "org.chromium.Chromium"
    }

    private func elementKey(_ element: AXUIElement) -> Int {
        Int(CFHash(element))
    }

    private func preview(_ text: String, maxLength: Int = 120) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: "\\n")
        if compact.count <= maxLength {
            return compact
        }
        let end = compact.index(compact.startIndex, offsetBy: maxLength)
        return String(compact[..<end]) + "..."
    }
}

enum SelectionError: LocalizedError {
    case notTrusted
    case noSelection

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            "WhyText 需要辅助功能权限才能读取选中文本。请在“系统设置 -> 隐私与安全性 -> 辅助功能”中开启（可在设置页点击按钮跳转）。"
        case .noSelection:
            "没有检测到选中文本。"
        }
    }
}

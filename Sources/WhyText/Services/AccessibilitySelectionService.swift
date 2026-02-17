import AppKit
import ApplicationServices
import Foundation

final class AccessibilitySelectionService {
    enum Status: Equatable {
        case trusted
        case notTrusted
    }

    func status() -> Status {
        isTrusted(prompt: false) ? .trusted : .notTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let options: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestPermissionPrompt() {
        // Avoid spamming the prompt if the user is clicking around.
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

    func getSelectedText() throws -> String {
        guard status() == .trusted else {
            throw SelectionError.notTrusted
        }

        let systemWide = AXUIElementCreateSystemWide()

        if let text = try selectedText(from: systemWide) {
            return text
        }

        throw SelectionError.noSelection
    }

    private func selectedText(from systemWide: AXUIElement) throws -> String? {
        var focusedElement: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        if focusedError == .success, let focusedElement {
            let element = unsafeBitCast(focusedElement, to: AXUIElement.self)
            return try selectedText(in: element)
        }

        var focusedApp: CFTypeRef?
        let appError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        if appError == .success, let focusedApp {
            let appElement = unsafeBitCast(focusedApp, to: AXUIElement.self)

            var appFocusedElement: CFTypeRef?
            let appFocusedError = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &appFocusedElement
            )
            if appFocusedError == .success, let appFocusedElement {
                let element = unsafeBitCast(appFocusedElement, to: AXUIElement.self)
                return try selectedText(in: element)
            }
        }

        return nil
    }

    private func selectedText(in element: AXUIElement) throws -> String? {
        if let text = copyStringAttribute(kAXSelectedTextAttribute as CFString, from: element) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var selectedRange: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        if rangeError == .success, let selectedRange,
           CFGetTypeID(selectedRange) == AXValueGetTypeID() {
            var rangeString: CFTypeRef?
            let paramError = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                selectedRange,
                &rangeString
            )

            if paramError == .success, let rangeString = rangeString as? String {
                return rangeString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? String
    }
}

enum SelectionError: LocalizedError {
    case notTrusted
    case noSelection

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            "WhyText 需要辅助功能权限才能读取选中文本。请在“系统设置 → 隐私与安全性 → 辅助功能”中开启（可在设置页点击按钮跳转）。"
        case .noSelection:
            "没有检测到选中文本。"
        }
    }
}

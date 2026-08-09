import AppKit
import Foundation
import WhyTextCore

@MainActor
final class SelectionAutoPopupCoordinator {
    private let selectionReader: SelectionReader
    private let selectionBubbleController: SelectionBubbleController

    private var selectionMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseDownLocation: NSPoint?
    private var lastAutoPopupText: String = ""
    private var lastAutoPopupAt = Date.distantPast
    private var pendingSelectionText: String = ""
    private var pendingSelectionAnchorRect: CGRect?
    private var suppressAutoPopupUntil = Date.distantPast
    private var autoPopupTask: Task<Void, Never>?

    private static let autoPopupDragThreshold: CGFloat = 4
    private static let autoPopupAnchorTolerance: CGFloat = 80

    /// Returns whether the translation panel is currently visible.
    var isPanelVisible: () -> Bool = { false }

    init(
        selectionReader: SelectionReader,
        selectionBubbleController: SelectionBubbleController
    ) {
        self.selectionReader = selectionReader
        self.selectionBubbleController = selectionBubbleController
    }

    deinit {
        if let selectionMonitor {
            NSEvent.removeMonitor(selectionMonitor)
        }
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
        autoPopupTask?.cancel()
    }

    var pendingText: String {
        pendingSelectionText
    }

    func setEnabled(_ enabled: Bool) {
        if let selectionMonitor {
            NSEvent.removeMonitor(selectionMonitor)
            self.selectionMonitor = nil
        }
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }

        autoPopupTask?.cancel()
        autoPopupTask = nil

        guard enabled else {
            clearPendingSelection()
            selectionBubbleController.hide()
            return
        }

        // Track mouse-down position so we can distinguish clicks from drag-selections.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.mouseDownLocation = NSEvent.mouseLocation
        }

        selectionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self else { return }
            let clickCount = event.clickCount
            self.autoPopupTask?.cancel()
            self.autoPopupTask = Task { @MainActor in
                await self.autoPopupOnSelectionIfNeeded(mouseUpClickCount: clickCount)
            }
        }
    }

    func handlePanelDidClose() {
        autoPopupTask?.cancel()
        autoPopupTask = nil
        clearPendingSelection()
        selectionBubbleController.hide()
        suppressAutoPopupUntil = Date().addingTimeInterval(0.9)
    }

    func hideBubble() {
        selectionBubbleController.hide()
    }

    private func clearPendingSelection() {
        pendingSelectionText = ""
        pendingSelectionAnchorRect = nil
        mouseDownLocation = nil
    }

    private func autoPopupOnSelectionIfNeeded(mouseUpClickCount: Int) async {
        if isPanelVisible() {
            return
        }

        let now = Date()
        if now < suppressAutoPopupUntil {
            return
        }

        let mouseUpLocation = NSEvent.mouseLocation
        guard let downLocation = mouseDownLocation else {
            return
        }

        let dx = mouseUpLocation.x - downLocation.x
        let dy = mouseUpLocation.y - downLocation.y
        let distance = sqrt(dx * dx + dy * dy)
        let didDragSelect = distance >= Self.autoPopupDragThreshold
        let didMultiClickSelect = mouseUpClickCount >= 2
        if !didDragSelect && !didMultiClickSelect {
            mouseDownLocation = nil
            return
        }
        mouseDownLocation = nil

        // Auto-popup never uses clipboard Cmd+C fallback or unanchored AX text —
        // both can surface unrelated/sensitive content from another control.
        let selection = await readSelectionForAutoPopup(near: mouseUpLocation)
        guard !Task.isCancelled else { return }
        if isPanelVisible() || Date() < suppressAutoPopupUntil {
            return
        }

        let trimmed = selection.text
        guard trimmed.count >= 2, selection.anchorRect != nil else {
            pendingSelectionText = ""
            pendingSelectionAnchorRect = nil
            return
        }

        if trimmed == lastAutoPopupText, now.timeIntervalSince(lastAutoPopupAt) < 0.6 {
            return
        }

        lastAutoPopupText = trimmed
        lastAutoPopupAt = now

        pendingSelectionText = trimmed
        pendingSelectionAnchorRect = selection.anchorRect

        let point = NSEvent.mouseLocation
        selectionBubbleController.show(at: point, anchorRect: selection.anchorRect)
    }

    private func readSelectionForAutoPopup(near mouseLocation: NSPoint) async -> SelectionReader.Result {
        // Try immediately, then back off — stop as soon as AX exposes a usable selection.
        let delays: [UInt64] = [0, 50_000_000, 120_000_000, 250_000_000]

        for delay in delays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else {
                return SelectionReader.Result(text: "", anchorRect: nil)
            }

            let selection = try? await selectionReader.readSelectedText(allowClipboardFallback: false)
            let trimmed = AccessibilitySelectionHelpers.sanitizeSelectedText(selection?.text ?? "")
            if trimmed.count >= 2,
               let anchorRect = selection?.anchorRect,
               isAutoPopupSelectionNearMouse(anchorRect: anchorRect, mouseLocation: mouseLocation) {
                return SelectionReader.Result(text: trimmed, anchorRect: anchorRect)
            }
        }

        return SelectionReader.Result(text: "", anchorRect: nil)
    }

    private func isAutoPopupSelectionNearMouse(anchorRect: CGRect, mouseLocation: NSPoint) -> Bool {
        let raw = NSRect(x: anchorRect.origin.x, y: anchorRect.origin.y, width: anchorRect.width, height: anchorRect.height)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let flipped = NSRect(
            x: anchorRect.origin.x,
            y: screenFrame.maxY - anchorRect.maxY,
            width: anchorRect.width,
            height: anchorRect.height
        )

        return [raw, flipped].contains { rect in
            rect.insetBy(dx: -Self.autoPopupAnchorTolerance, dy: -Self.autoPopupAnchorTolerance).contains(mouseLocation)
        }
    }
}

import AppKit
import Foundation
import WhyTextCore

@MainActor
final class SelectionAutoPopupCoordinator {
    private let selectionReader: SelectionReader
    private let selectionBubbleController: SelectionBubbleController

    private var selectionMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    /// Off-main global monitors must not touch MainActor state; this box is the seam.
    private let gestureTracker = GestureTracker()
    private var lastAutoPopupText: String = ""
    private var lastAutoPopupAt = Date.distantPast
    private var pendingSelectionText: String = ""
    private var pendingSelectionAnchorRect: CGRect?
    private var pendingSelectionSource: LookupSource?
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
        if let mouseDraggedMonitor {
            NSEvent.removeMonitor(mouseDraggedMonitor)
        }
        autoPopupTask?.cancel()
    }

    var pendingText: String {
        pendingSelectionText
    }

    /// Captured with `pendingText`, before the bubble click moves focus around.
    var pendingSource: LookupSource? {
        pendingSelectionSource
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
        if let mouseDraggedMonitor {
            NSEvent.removeMonitor(mouseDraggedMonitor)
            self.mouseDraggedMonitor = nil
        }

        autoPopupTask?.cancel()
        autoPopupTask = nil
        gestureTracker.clear()

        BubbleDebugLog.log("setEnabled(\(enabled))")

        guard enabled else {
            clearPendingSelection()
            selectionBubbleController.hide()
            return
        }

        // Record gesture state synchronously in the monitor callbacks (may be
        // off-main). Only hop to MainActor once we have a complete mouseUp.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [gestureTracker] _ in
            let location = NSEvent.mouseLocation
            gestureTracker.mouseDown(at: location)
            BubbleDebugLog.log("mouseDown at \(location) main=\(Thread.isMainThread)")
        }

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [gestureTracker] _ in
            gestureTracker.mouseDragged()
        }

        selectionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self, gestureTracker] event in
            let clickCount = event.clickCount
            let upLocation = NSEvent.mouseLocation
            guard let gesture = gestureTracker.consumeMouseUp(
                at: upLocation,
                dragThreshold: Self.autoPopupDragThreshold
            ) else {
                BubbleDebugLog.log("mouseUp clicks=\(clickCount) gate: no mouseDownLocation")
                return
            }

            BubbleDebugLog.log(
                "mouseUp clicks=\(clickCount) distance=\(String(format: "%.1f", gesture.distance)) draggedEvent=\(gesture.sawDragEvent) drag=\(gesture.didDragSelect) multi=\(clickCount >= 2)"
            )

            DispatchQueue.main.async {
                guard let self else { return }
                self.autoPopupTask?.cancel()
                self.autoPopupTask = Task { @MainActor in
                    await self.autoPopupOnSelectionIfNeeded(
                        mouseUpClickCount: clickCount,
                        mouseUpLocation: upLocation,
                        didDragSelect: gesture.didDragSelect
                    )
                }
            }
        }

        BubbleDebugLog.log(
            "monitors installed down=\(mouseDownMonitor != nil) drag=\(mouseDraggedMonitor != nil) up=\(selectionMonitor != nil)"
        )
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
        pendingSelectionSource = nil
        gestureTracker.clear()
    }

    private func autoPopupOnSelectionIfNeeded(
        mouseUpClickCount: Int,
        mouseUpLocation: NSPoint,
        didDragSelect: Bool
    ) async {
        if isPanelVisible() {
            BubbleDebugLog.log("gate: panel visible")
            return
        }

        let now = Date()
        if now < suppressAutoPopupUntil {
            BubbleDebugLog.log("gate: suppressed until \(suppressAutoPopupUntil)")
            return
        }

        let didMultiClickSelect = mouseUpClickCount >= 2
        if !didDragSelect && !didMultiClickSelect {
            BubbleDebugLog.log("gate: not an intentional selection gesture")
            return
        }

        // Prefer AX text (with or without a trustworthy anchor). When AX is empty,
        // intentional gestures may use the clipboard Cmd+C fallback — same as the
        // pre-778c115 path that users relied on in Chrome / Electron / PDF viewers.
        let allowMissingAnchor = didDragSelect || didMultiClickSelect
        let selection = await readSelectionForAutoPopup(
            near: mouseUpLocation,
            allowMissingAnchor: allowMissingAnchor
        )
        guard !Task.isCancelled else {
            BubbleDebugLog.log("gate: task cancelled after read")
            return
        }
        if isPanelVisible() || Date() < suppressAutoPopupUntil {
            BubbleDebugLog.log("gate: panel visible or suppressed after read")
            return
        }

        let trimmed = selection.text
        guard trimmed.count >= SelectionAutoPopupPolicy.minimumTextLength else {
            BubbleDebugLog.log("gate: final text too short len=\(trimmed.count)")
            pendingSelectionText = ""
            pendingSelectionAnchorRect = nil
            pendingSelectionSource = nil
            return
        }

        if trimmed == lastAutoPopupText, now.timeIntervalSince(lastAutoPopupAt) < 0.6 {
            BubbleDebugLog.log("gate: dedupe same text within 0.6s")
            return
        }

        lastAutoPopupText = trimmed
        lastAutoPopupAt = now

        pendingSelectionText = trimmed
        pendingSelectionAnchorRect = selection.anchorRect
        pendingSelectionSource = selection.source

        let point = NSEvent.mouseLocation
        BubbleDebugLog.log("SHOW bubble at \(point) anchor=\(selection.anchorRect?.debugDescription ?? "nil") textLen=\(trimmed.count)")
        selectionBubbleController.show(at: point, anchorRect: selection.anchorRect)
    }

    private func readSelectionForAutoPopup(
        near mouseLocation: NSPoint,
        allowMissingAnchor: Bool
    ) async -> SelectionReader.Result {
        // Try immediately, then back off — stop as soon as AX exposes a usable selection.
        let delays: [UInt64] = [0, 50_000_000, 120_000_000, 250_000_000]

        for delay in delays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else {
                BubbleDebugLog.log("read[\(delay / 1_000_000)ms]: task cancelled")
                return SelectionReader.Result(text: "", anchorRect: nil)
            }

            var selection: SelectionReader.Result?
            var readError: String?
            do {
                selection = try await selectionReader.readSelectedText(allowClipboardFallback: false)
            } catch {
                readError = String(describing: error)
            }
            let trimmed = AccessibilitySelectionHelpers.sanitizeSelectedText(selection?.text ?? "")
            let anchorRect = selection?.anchorRect
            let nearMouse = anchorRect.map {
                isAutoPopupSelectionNearMouse(anchorRect: $0, mouseLocation: mouseLocation)
            } ?? false

            let accepted = SelectionAutoPopupPolicy.acceptsAXSelection(
                textLength: trimmed.count,
                hasAnchorRect: anchorRect != nil,
                anchorNearMouse: nearMouse,
                allowMissingAnchor: allowMissingAnchor
            )
            BubbleDebugLog.log(
                "read[\(delay / 1_000_000)ms]: error=\(readError ?? "nil") textLen=\(trimmed.count) anchor=\(anchorRect != nil) nearMouse=\(nearMouse) allowMissingAnchor=\(allowMissingAnchor) accepted=\(accepted)"
            )

            if accepted {
                // Drop untrustworthy anchors so the bubble parks near the mouse.
                let usableAnchor = nearMouse ? anchorRect : nil
                return SelectionReader.Result(text: trimmed, anchorRect: usableAnchor, source: selection?.source)
            }
        }

        if allowMissingAnchor {
            BubbleDebugLog.log("read: trying clipboard fallback")
            if let fallback = try? await selectionReader.readSelectedText(allowClipboardFallback: true) {
                let fallbackText = AccessibilitySelectionHelpers.sanitizeSelectedText(fallback.text)
                if fallbackText.count >= SelectionAutoPopupPolicy.minimumTextLength {
                    BubbleDebugLog.log("read: clipboard fallback ok textLen=\(fallbackText.count)")
                    return SelectionReader.Result(text: fallbackText, anchorRect: nil, source: fallback.source)
                }
            }
            BubbleDebugLog.log("read: clipboard fallback empty")
        }

        BubbleDebugLog.log("read: all attempts rejected")
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

/// Thread-safe mouse gesture state for global event monitors.
private final class GestureTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var mouseDownLocation: NSPoint?
    private var sawDragEvent = false

    struct Outcome {
        var distance: CGFloat
        var sawDragEvent: Bool
        var didDragSelect: Bool
    }

    func mouseDown(at point: NSPoint) {
        lock.lock()
        mouseDownLocation = point
        sawDragEvent = false
        lock.unlock()
    }

    func mouseDragged() {
        lock.lock()
        if mouseDownLocation != nil {
            sawDragEvent = true
        }
        lock.unlock()
    }

    func consumeMouseUp(at point: NSPoint, dragThreshold: CGFloat) -> Outcome? {
        lock.lock()
        defer { lock.unlock() }

        guard let down = mouseDownLocation else { return nil }
        let dx = point.x - down.x
        let dy = point.y - down.y
        let distance = sqrt(dx * dx + dy * dy)
        let dragged = sawDragEvent
        mouseDownLocation = nil
        sawDragEvent = false
        // Require real pointer travel. A lone leftMouseDragged with ~0 distance
        // (trackpad noise / click jitter) must not count as text selection —
        // that falsely triggers clipboard fallback and a system beep.
        return Outcome(
            distance: distance,
            sawDragEvent: dragged,
            didDragSelect: distance >= dragThreshold
        )
    }

    func clear() {
        lock.lock()
        mouseDownLocation = nil
        sawDragEvent = false
        lock.unlock()
    }
}

import AppKit
import SwiftUI

final class SelectionBubbleController: NSObject, NSWindowDelegate {
    var onTap: (() -> Void)?

    private var panel: NSPanel?
    private var outsideEventMonitor: Any?
    private var autoDismissTask: Task<Void, Never>?

    func show(at mouseLocation: NSPoint, anchorRect: CGRect? = nil) {
        autoDismissTask?.cancel()

        let size = NSSize(width: 34, height: 28)
        let hostingView = NSHostingView(rootView: SelectionBubbleButton { [weak self] in
            self?.handleTap()
        })

        if let panel {
            panel.contentView = hostingView
            positionBubble(panel: panel, at: mouseLocation, anchorRect: anchorRect, size: size)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            startOutsideEventMonitor()
            scheduleAutoDismiss()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
        panel.delegate = self

        self.panel = panel

        positionBubble(panel: panel, at: mouseLocation, anchorRect: anchorRect, size: size)

        // Fade in
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        startOutsideEventMonitor()
        scheduleAutoDismiss()
    }

    func hide() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        stopOutsideEventMonitor()

        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.close()
            self?.panel = nil
        })
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func windowWillClose(_ notification: Notification) {
        autoDismissTask?.cancel()
        stopOutsideEventMonitor()
        panel = nil
    }

    private func handleTap() {
        autoDismissTask?.cancel()
        stopOutsideEventMonitor()
        panel?.close()
        panel = nil
        onTap?()
    }

    private func positionBubble(panel: NSPanel, at mouseLocation: NSPoint, anchorRect: CGRect?, size: NSSize) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let offsetX: CGFloat = 8
        let offsetY: CGFloat = 6

        var x: CGFloat
        var y: CGFloat

        if let anchor = normalizedAnchorRect(anchorRect, near: mouseLocation, screen: screen) {
            x = anchor.maxX + offsetX
            y = anchor.midY - size.height / 2

            if x + size.width > visibleFrame.maxX {
                x = anchor.minX - size.width - offsetX
            }
            if y + size.height > visibleFrame.maxY {
                y = anchor.maxY - size.height
            }
            if y < visibleFrame.minY {
                y = anchor.minY
            }
        } else {
            x = mouseLocation.x + offsetX
            y = mouseLocation.y + offsetY
        }

        if x + size.width > visibleFrame.maxX {
            x = mouseLocation.x - size.width - offsetX
        }
        if y + size.height > visibleFrame.maxY {
            y = mouseLocation.y - size.height - offsetY
        }

        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func normalizedAnchorRect(_ rect: CGRect?, near mouseLocation: NSPoint, screen: NSScreen?) -> CGRect? {
        guard let rect, rect.width > 0, rect.height > 0 else {
            return nil
        }

        let targetScreen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let screenFrame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let raw = NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
        let flipped = NSRect(
            x: rect.origin.x,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let candidates = [raw, flipped].filter { candidate in
            candidate.intersects(screenFrame.insetBy(dx: -80, dy: -80))
        }

        guard !candidates.isEmpty else {
            return nil
        }

        return candidates.min { lhs, rhs in
            lhs.distance(to: mouseLocation) < rhs.distance(to: mouseLocation)
        }
    }

    /// Auto-dismiss after 4 seconds if user doesn't interact.
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func startOutsideEventMonitor() {
        stopOutsideEventMonitor()

        outsideEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            let point = NSEvent.mouseLocation
            if panel.frame.insetBy(dx: -6, dy: -6).contains(point) {
                return
            }
            self.hide()
        }
    }

    private func stopOutsideEventMonitor() {
        if let outsideEventMonitor {
            NSEvent.removeMonitor(outsideEventMonitor)
            self.outsideEventMonitor = nil
        }
    }
}

private extension NSRect {
    func distance(to point: NSPoint) -> CGFloat {
        if contains(point) {
            return 0
        }

        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Bubble View

/// A compact action pill near the selected text. It stays quiet at rest,
/// then reveals the translate affordance on hover.
private struct SelectionBubbleButton: View {
    var onTap: () -> Void
    @State private var isHovering = false
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "character.textbox")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: isHovering ? 34 : 28, height: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(isHovering ? 0.92 : 0.62))
                        .shadow(color: Color.accentColor.opacity(isHovering ? 0.22 : 0.10), radius: isHovering ? 6 : 3, y: 1)
                )
                .scaleEffect(appeared ? 1.0 : 0.01)
                .opacity(appeared ? 1 : 0)
                .animation(AstryxMotion.quick, value: isHovering)
                // Keep a generous hit area so it's easy to click.
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            withAnimation(.astryxSpring(response: 0.35, damping: 0.65)) {
                appeared = true
            }
        }
        .help("翻译")
    }
}

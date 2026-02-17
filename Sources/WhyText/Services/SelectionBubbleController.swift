import AppKit
import SwiftUI

final class SelectionBubbleController: NSObject, NSWindowDelegate {
    var onTap: (() -> Void)?

    private var panel: NSPanel?
    private var outsideEventMonitor: Any?
    private var autoDismissTask: Task<Void, Never>?

    func show(at mouseLocation: NSPoint) {
        autoDismissTask?.cancel()

        let size = NSSize(width: 24, height: 24)
        let hostingView = NSHostingView(rootView: SelectionBubbleButton { [weak self] in
            self?.handleTap()
        })

        if let panel {
            panel.contentView = hostingView
            positionBubble(panel: panel, at: mouseLocation, size: size)
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

        positionBubble(panel: panel, at: mouseLocation, size: size)

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

    private func positionBubble(panel: NSPanel, at mouseLocation: NSPoint, size: NSSize) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let offsetX: CGFloat = 8
        let offsetY: CGFloat = 4

        var x = mouseLocation.x + offsetX
        var y = mouseLocation.y + offsetY

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

// MARK: - Bubble View

/// A tiny accent-colored dot. No icon, no text — just a quiet hint.
/// On hover it grows slightly and gains a soft glow.
private struct SelectionBubbleButton: View {
    var onTap: () -> Void
    @State private var isHovering = false
    @State private var appeared = false

    private let restSize: CGFloat = 10
    private let hoverSize: CGFloat = 14

    var body: some View {
        Button(action: onTap) {
            let size = isHovering ? hoverSize : restSize

            Circle()
                .fill(Color.accentColor.opacity(isHovering ? 0.85 : 0.5))
                .frame(width: size, height: size)
                .shadow(color: Color.accentColor.opacity(isHovering ? 0.3 : 0), radius: 6, y: 0)
                .scaleEffect(appeared ? 1.0 : 0.01)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                // Keep a 24x24 hit area so it's easy to click
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
        }
        .help("翻译")
    }
}

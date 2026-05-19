import AppKit
import SwiftUI

final class FloatingPanelController: NSObject, NSWindowDelegate {
    var onDidClose: (() -> Void)?

    private var panel: NSPanel?
    private var mouseOrigin: NSPoint = .zero
    private var isClosingProgrammatically = false

    private let maxWidth: CGFloat = 420
    private let minWidth: CGFloat = 200
    private let maxHeight: CGFloat = 480
    private let minHeight: CGFloat = 60

    func show<V: View>(at mouseLocation: NSPoint, @ViewBuilder content: () -> V) {
        mouseOrigin = mouseLocation

        let rootView = AnyView(content())
        let hostingView = NSHostingView(rootView: rootView)

        if let panel {
            panel.contentView = hostingView
            fitAndPosition(panel: panel, hostingView: hostingView)
            panel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let initialSize = NSSize(width: minWidth, height: minHeight)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.title = "WhyText"
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.contentView = hostingView

        self.panel = panel

        fitAndPosition(panel: panel, hostingView: hostingView)

        // Spring-like entrance: scale up from center + fade in.
        // We simulate scale by starting slightly smaller and expanding.
        let finalFrame = panel.frame
        let scaleFactor: CGFloat = 0.94
        let shrunkWidth = finalFrame.width * scaleFactor
        let shrunkHeight = finalFrame.height * scaleFactor
        let offsetX = (finalFrame.width - shrunkWidth) / 2
        let offsetY = (finalFrame.height - shrunkHeight) / 2
        let startFrame = NSRect(
            x: finalFrame.origin.x + offsetX,
            y: finalFrame.origin.y + offsetY,
            width: shrunkWidth,
            height: shrunkHeight
        )

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }

    }

    /// Refit the panel to its current content size, keeping the top-left anchored.
    func refit() {
        guard let panel, let hostingView = panel.contentView as? NSHostingView<AnyView> else { return }

        let fitting = hostingView.fittingSize
        let w = min(max(fitting.width, minWidth), maxWidth)
        let h = min(max(fitting.height, minHeight), maxHeight)
        let newSize = NSSize(width: w, height: h)

        guard abs(panel.frame.width - w) > 1 || abs(panel.frame.height - h) > 1 else { return }

        var frame = panel.frame
        let topY = frame.origin.y + frame.size.height
        frame.size = newSize
        frame.origin.y = topY - newSize.height
        panel.setFrame(frame, display: true, animate: false)
    }

    func close() {
        let wasVisible = panel != nil

        if let panel {
            isClosingProgrammatically = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.panel?.close()
                self?.panel = nil
                self?.isClosingProgrammatically = false
            })
        }

        if wasVisible {
            onDidClose?()
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        if !isClosingProgrammatically {
            onDidClose?()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
    }

    func bringToFrontIfVisible() {
        guard let panel, panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    private func fitAndPosition(panel: NSPanel, hostingView: NSHostingView<AnyView>) {
        let fitting = hostingView.fittingSize
        let w = min(max(fitting.width, minWidth), maxWidth)
        let h = min(max(fitting.height, minHeight), maxHeight)
        let size = NSSize(width: w, height: h)

        panel.setContentSize(size)
        let origin = ScreenClamp.positionedOrigin(near: mouseOrigin, size: size)
        panel.setFrameOrigin(origin)
    }
}

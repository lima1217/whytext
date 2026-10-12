import AppKit
import SwiftUI

final class FloatingPanelController: NSObject, NSWindowDelegate {
    var onDidClose: (() -> Void)?
    /// Called for a mouse-down in another app while the panel is open.
    var onOutsideClick: (() -> Void)?
    /// Checked before `onOutsideClick`; returning false keeps the panel open (pinned).
    var shouldCloseOnOutsideClick: () -> Bool = { true }

    private var panel: NSPanel?
    private var titlebarAccessory: NSTitlebarAccessoryViewController?
    private var titlebarHostingView: NSHostingView<AnyView>?
    private var mouseOrigin: NSPoint = .zero
    private var isClosingProgrammatically = false
    private var outsideClickMonitor: Any?

    /// Cap the reading column near ~60–75 Latin / ~30–35 CJK glyphs at default body size.
    private let maxWidth: CGFloat = 560
    private let minWidth: CGFloat = 280
    private let maxHeight: CGFloat = 560
    private let minHeight: CGFloat = 60

    func show<Content: View, Titlebar: View>(
        at mouseLocation: NSPoint,
        @ViewBuilder titlebar: () -> Titlebar,
        @ViewBuilder content: () -> Content
    ) {
        mouseOrigin = mouseLocation

        let rootView = AnyView(content())
        let hostingView = NSHostingView(rootView: rootView)
        prepareHostingView(hostingView)
        let titlebarView = AnyView(titlebar())

        if let panel {
            panel.contentView = hostingView
            fitAndPosition(panel: panel, hostingView: hostingView)
            updateTitlebarAccessory(panel: panel, rootView: titlebarView)
            panel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            installOutsideClickMonitor()
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.title = "WhyText"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.contentView = hostingView
        disableFullscreen(panel)

        self.panel = panel
        installTitlebarAccessory(panel: panel, rootView: titlebarView)

        fitAndPosition(panel: panel, hostingView: hostingView)

        // Symmetric present path: scale from center + fade (mirrored on dismiss).
        let finalFrame = panel.frame
        PanelChromeMotion.animatePresent(panel: panel, to: finalFrame)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitor()
    }

    /// A global monitor only sees events bound for other apps, so clicks on the panel,
    /// the selection bubble, or Settings never close it.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible, self.shouldCloseOnOutsideClick() else { return }
            self.onOutsideClick?()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    /// Refit the panel to its current content size, keeping the top-left anchored.
    /// Without `force`, a panel already at max height is left alone: streamed text
    /// only grows, and measuring `fittingSize` lays out the whole result each time.
    func refit(force: Bool = false) {
        guard let panel, let hostingView = panel.contentView as? NSHostingView<AnyView> else { return }
        if !force, panel.frame.height >= maxHeight - 1 { return }

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
        removeOutsideClickMonitor()

        if let panel {
            isClosingProgrammatically = true
            // Leave the way we arrived (scale + fade) — Apple spatial consistency.
            PanelChromeMotion.animateDismiss(panel: panel) { [weak self] in
                self?.panel?.close()
                self?.panel = nil
                self?.isClosingProgrammatically = false
            }
        }

        if wasVisible {
            onDidClose?()
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func windowWillClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        panel = nil
        if !isClosingProgrammatically {
            onDidClose?()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        updateTitlebarAccessoryWidth(panel: panel)
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
        updateTitlebarAccessoryWidth(panel: panel)
    }

    private func installTitlebarAccessory(panel: NSPanel, rootView: AnyView) {
        let hostingView = NSHostingView(rootView: rootView)
        prepareHostingView(hostingView)
        hostingView.frame = NSRect(origin: .zero, size: titlebarAccessorySize(for: panel))

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        accessory.view = hostingView

        panel.addTitlebarAccessoryViewController(accessory)
        titlebarAccessory = accessory
        titlebarHostingView = hostingView
    }

    private func updateTitlebarAccessory(panel: NSPanel, rootView: AnyView) {
        if titlebarAccessory == nil {
            installTitlebarAccessory(panel: panel, rootView: rootView)
            return
        }

        titlebarHostingView?.rootView = rootView
        updateTitlebarAccessoryWidth(panel: panel)
    }

    private func updateTitlebarAccessoryWidth(panel: NSPanel) {
        titlebarHostingView?.frame.size = titlebarAccessorySize(for: panel)
    }

    private func titlebarAccessorySize(for panel: NSPanel) -> NSSize {
        NSSize(width: max(panel.frame.width - 78, 160), height: 32)
    }

    private func prepareHostingView(_ hostingView: NSHostingView<AnyView>) {
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func disableFullscreen(_ panel: NSPanel) {
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

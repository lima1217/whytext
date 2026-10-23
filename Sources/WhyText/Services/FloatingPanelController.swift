import AppKit
import SwiftUI
import WhyTextCore

final class FloatingPanelController: NSObject, NSWindowDelegate {
    var onDidClose: (() -> Void)?
    /// Called for a mouse-down in another app while the panel is open.
    var onOutsideClick: (() -> Void)?
    /// Checked before `onOutsideClick`; returning false keeps the panel open (pinned).
    var shouldCloseOnOutsideClick: () -> Bool = { true }

    private var panel: NSPanel?
    private var titlebarAccessory: NSTitlebarAccessoryViewController?
    private var titlebarHostingView: NSHostingView<AnyView>?
    private var placement: PanelPlacement?
    /// Where the panel is headed; it may still be gliding there.
    private var targetFrame: NSRect?
    private var isClosingProgrammatically = false
    private var outsideClickMonitor: Any?
    /// Set when the user starts dragging the panel; their position then wins.
    private var isUserMoving = false
    /// Bumped by every show and close, so a dismiss that finishes after the panel was
    /// shown again doesn't close the new one.
    private var presentationID = 0

    /// Cap the reading column near ~60–75 Latin / ~30–35 CJK glyphs at default body size.
    private let maxWidth: CGFloat = 560
    private let minWidth: CGFloat = 280
    private let maxHeight: CGFloat = 560
    private let minHeight: CGFloat = 60

    /// Shows the panel beside `selectionRect` (Accessibility coordinates), or beside
    /// the pointer when the selection's position is unknown. With `sourceFrame` (the
    /// selection bubble, in screen coordinates) the panel emerges from it.
    func show<Content: View, Titlebar: View>(
        at mouseLocation: NSPoint,
        selectionRect: CGRect? = nil,
        emergingFrom sourceFrame: NSRect? = nil,
        @ViewBuilder titlebar: () -> Titlebar,
        @ViewBuilder content: () -> Content
    ) {
        presentationID += 1
        isClosingProgrammatically = false

        let hostingView = NSHostingView(rootView: AnyView(content()))
        prepareHostingView(hostingView)
        let titlebarView = AnyView(titlebar())

        let panel = self.panel ?? makePanel()
        let isNew = self.panel == nil
        self.panel = panel
        panel.contentView = hostingView
        if isNew {
            installTitlebarAccessory(panel: panel, rootView: titlebarView)
        } else {
            updateTitlebarAccessory(panel: panel, rootView: titlebarView)
        }

        let placement = makePlacement(mouseLocation: mouseLocation, selectionRect: selectionRect)
        self.placement = placement
        let size = fittingSize(of: hostingView, placement: placement)
        let finalFrame = placement.frame(for: size)
        targetFrame = finalFrame

        // Slide away from the text, or fly out of the bubble.
        let startOrigin: NSPoint
        if let sourceFrame {
            startOrigin = placement.origin(for: size, emergingFrom: sourceFrame)
        } else {
            let toward: CGFloat = placement.growth == .down ? PanelChromeMotion.slideDistance : -PanelChromeMotion.slideDistance
            startOrigin = NSPoint(x: finalFrame.minX, y: finalFrame.minY + toward)
        }
        PanelChromeMotion.present(panel: panel, to: finalFrame, from: startOrigin)
        updateTitlebarAccessoryWidth(panel: panel)

        // Key, but WhyText stays in the background: the app being read keeps its
        // focus and selection, and gets the keyboard back as soon as the panel closes.
        panel.makeKey()
        installOutsideClickMonitor()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: minWidth, height: minHeight)),
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
        disableFullscreen(panel)
        return panel
    }

    private func makePlacement(mouseLocation: NSPoint, selectionRect: CGRect?) -> PanelPlacement {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.maxY ?? 900
        // Without a selection rectangle, treat the pointer as sitting on the line being read.
        let anchor = selectionRect.flatMap {
            AXGeometry.cocoaRect(fromAX: $0, primaryScreenHeight: primaryHeight, screens: screens.map(\.frame), near: mouseLocation)
        } ?? NSRect(x: mouseLocation.x, y: mouseLocation.y - 12, width: 1, height: 24)

        let screen = screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return PanelPlacement.make(anchor: anchor, visibleFrame: visibleFrame, preferredMaxHeight: maxHeight)
    }

    private func fittingSize(of hostingView: NSHostingView<AnyView>, placement: PanelPlacement) -> NSSize {
        let fitting = hostingView.fittingSize
        return NSSize(
            width: min(max(fitting.width, minWidth), maxWidth),
            height: min(max(fitting.height, minHeight), placement.maxHeight)
        )
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

    /// Refit the panel to its current content size, keeping the edge next to the
    /// selection fixed. Without `force`, a panel already at its tallest is left alone:
    /// streamed text only grows, and measuring `fittingSize` lays out the whole result.
    func refit(force: Bool = false) {
        guard let panel, let placement, let hostingView = panel.contentView as? NSHostingView<AnyView> else { return }
        let target = targetFrame ?? panel.frame
        if !force, target.height >= placement.maxHeight - 1 { return }

        let frame = placement.frame(for: fittingSize(of: hostingView, placement: placement))
        guard abs(target.width - frame.width) > 1 || abs(target.height - frame.height) > 1
            || abs(target.minY - frame.minY) > 1 else { return }
        targetFrame = frame
        // Glide, even mid-present: the animation retargets instead of waiting.
        PanelChromeMotion.resize(panel: panel, to: frame)
    }

    func close() {
        let wasVisible = panel != nil
        removeOutsideClickMonitor()

        if let panel {
            presentationID += 1
            let id = presentationID
            isClosingProgrammatically = true
            // Leave toward the text it came from, mirroring the way it arrived.
            let toward: CGFloat = placement?.growth == .up ? -PanelChromeMotion.slideDistance : PanelChromeMotion.slideDistance
            PanelChromeMotion.dismiss(panel: panel, offset: CGVector(dx: 0, dy: toward)) { [weak self] in
                // Shown again before the dismiss finished: that panel stays.
                guard let self, self.presentationID == id else { return }
                self.panel?.close()
                self.panel = nil
                self.placement = nil
                self.targetFrame = nil
                self.isClosingProgrammatically = false
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
        placement = nil
        targetFrame = nil
        if !isClosingProgrammatically {
            onDidClose?()
        }
    }

    /// Only user drags send this; programmatic frame changes don't.
    func windowWillMove(_ notification: Notification) {
        isUserMoving = true
    }

    func windowDidMove(_ notification: Notification) {
        guard isUserMoving, let panel, let placement else { return }
        isUserMoving = false
        self.placement = placement.moved(to: panel.frame, preferredMaxHeight: maxHeight)
        targetFrame = panel.frame
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
        // The panel is sized by `show`/`refit` from `fittingSize`. A minimum-size
        // constraint would instead measure wrapping text at its narrowest and force the
        // window far too tall (seen with two-line Japanese hints).
        hostingView.sizingOptions = [.intrinsicContentSize]
    }

    private func disableFullscreen(_ panel: NSPanel) {
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

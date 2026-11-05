import AppKit
import SwiftUI
import WhyTextCore

final class SelectionBubbleController: NSObject, NSWindowDelegate {
    /// Receive the bubble's frame, so the panel can grow out of where it was.
    var onTranslate: ((NSRect?) -> Void)?
    var onExplain: ((NSRect?) -> Void)?

    private var panel: NSPanel?
    /// Bumped by every show and hide, so a fade-out that finishes after the bubble
    /// was shown again doesn't close the new one.
    private var presentationID = 0
    private var outsideEventMonitor: Any?
    private var autoDismissTask: Task<Void, Never>?
    private var isHoverPaused = false

    func show(at mouseLocation: NSPoint, anchorRect: CGRect? = nil) {
        autoDismissTask?.cancel()
        isHoverPaused = false
        presentationID += 1

        let hostingView = NSHostingView(rootView: SelectionBubbleBar(
            onTranslate: { [weak self] in
                self?.handleAction(self?.onTranslate)
            },
            onExplain: { [weak self] in
                self?.handleAction(self?.onExplain)
            },
            onHoverChange: { [weak self] hovering in
                self?.setHoverPaused(hovering)
            }
        ))
        Self.prepareHostingView(hostingView)
        // Labels are localized, so the bubble takes the width its content needs.
        let size = hostingView.fittingSize

        if let panel {
            panel.setContentSize(size)
            panel.contentView = hostingView
            positionBubble(panel: panel, at: mouseLocation, anchorRect: anchorRect, size: size)
            // Picks up from a half-finished fade-out instead of popping to full opacity.
            PanelChromeMotion.present(panel: panel, to: panel.frame)
            panel.invalidateShadow()
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
        // Window shadow follows opaque content alpha — use this instead of a SwiftUI
        // `.shadow` clipped by the rectangular panel frame (which left sharp corners).
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
        panel.delegate = self

        self.panel = panel

        positionBubble(panel: panel, at: mouseLocation, anchorRect: anchorRect, size: size)
        PanelChromeMotion.present(panel: panel, to: panel.frame)
        panel.invalidateShadow()

        startOutsideEventMonitor()
        scheduleAutoDismiss()
    }

    func hide() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isHoverPaused = false
        stopOutsideEventMonitor()

        guard let panel else { return }

        presentationID += 1
        let id = presentationID
        PanelChromeMotion.dismiss(panel: panel) { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.panel?.close()
            self.panel = nil
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func windowWillClose(_ notification: Notification) {
        autoDismissTask?.cancel()
        stopOutsideEventMonitor()
        panel = nil
    }

    /// The bubble fades where it is while the panel grows out of its frame.
    private func handleAction(_ action: ((NSRect?) -> Void)?) {
        let frame = panel?.frame
        hide()
        action?(frame)
    }

    private func positionBubble(panel: NSPanel, at mouseLocation: NSPoint, anchorRect: CGRect?, size: NSSize) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let offsetX: CGFloat = 8
        let offsetY: CGFloat = 6

        var x: CGFloat
        var y: CGFloat

        if let anchor = normalizedAnchorRect(anchorRect, near: mouseLocation) {
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

    private func normalizedAnchorRect(_ rect: CGRect?, near mouseLocation: NSPoint) -> CGRect? {
        guard let rect else { return nil }
        let screens = NSScreen.screens
        return AXGeometry.cocoaRect(
            fromAX: rect,
            primaryScreenHeight: screens.first?.frame.maxY ?? 900,
            screens: screens.map(\.frame),
            near: mouseLocation
        )
    }

    /// Auto-dismiss after 6 seconds unless the pointer is over the bubble (pause/resume).
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard !isHoverPaused else { return }
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            guard !self.isHoverPaused else { return }
            self.hide()
        }
    }

    private func setHoverPaused(_ hovering: Bool) {
        isHoverPaused = hovering
        if hovering {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        } else if panel != nil {
            scheduleAutoDismiss()
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

    private static func prepareHostingView<Content: View>(_ hostingView: NSHostingView<Content>) {
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// MARK: - Bubble View

/// Compact dual-action bar near the selected text: translate + explain.
/// Translucent material chrome with the result panel's quiet icon buttons, so it
/// reads as WhyText without stealing focus from the selection.
private struct SelectionBubbleBar: View {
    var onTranslate: () -> Void
    var onExplain: () -> Void
    var onHoverChange: (Bool) -> Void

    @State private var appeared = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            QuietLabelButton(
                title: L10n.t("翻译"),
                systemName: "character.bubble",
                action: onTranslate
            )
            Rectangle()
                .fill(AstryxColor.border)
                .frame(width: 1, height: Metrics.dividerHeight)
                .accessibilityHidden(true)
            QuietLabelButton(
                title: L10n.t("解释"),
                systemName: "questionmark.circle",
                action: onExplain
            )
        }
        .padding(Metrics.padding)
        .background(bubbleMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(materialEdgeHighlight, lineWidth: 0.5)
        )
        // No SwiftUI drop shadow — the panel uses `hasShadow` so the silhouette
        // follows the rounded alpha instead of the rectangular window bounds.
        .scaleEffect(appeared || MotionPreference.reduceMotion ? 1.0 : 0.94)
        .opacity(appeared || MotionPreference.reduceMotion ? 1 : 0)
        .onHover { onHoverChange($0) }
        .onAppear {
            guard !MotionPreference.reduceMotion else {
                appeared = true
                return
            }
            // Critically damped — no bounce on chrome that simply appears.
            withAnimation(AstryxMotion.present) {
                appeared = true
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("WhyText 操作"))
    }

    private var bubbleMaterial: some View {
        ZStack {
            if MotionPreference.reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                // cornerStyle masks at CALayer — SwiftUI clipShape alone does not clip materials.
                VisualEffectView(
                    material: .popover,
                    blendingMode: .behindWindow,
                    state: .active,
                    cornerStyle: .continuous(Metrics.radius)
                )
                Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.2 : 0.45)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
    }

    /// Bright rim — materials read as thicker when lit at the edge.
    private var materialEdgeHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.08)
    }
}

private enum Metrics {
    /// Concentric with the button hover fill: radius = `Radius.element` + padding.
    static let radius: CGFloat = Radius.element + padding
    static let padding: CGFloat = 4
    static let spacing: CGFloat = 2
    static let dividerHeight: CGFloat = 16
}

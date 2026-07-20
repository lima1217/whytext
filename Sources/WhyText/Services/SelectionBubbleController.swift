import AppKit
import SwiftUI

final class SelectionBubbleController: NSObject, NSWindowDelegate {
    var onTranslate: (() -> Void)?
    var onExplain: (() -> Void)?

    private var panel: NSPanel?
    private var outsideEventMonitor: Any?
    private var autoDismissTask: Task<Void, Never>?

    private static let bubbleSize = NSSize(width: 80, height: 32)

    func show(at mouseLocation: NSPoint, anchorRect: CGRect? = nil) {
        autoDismissTask?.cancel()

        let size = Self.bubbleSize
        let hostingView = NSHostingView(rootView: SelectionBubbleBar(
            onTranslate: { [weak self] in
                self?.handleAction(self?.onTranslate)
            },
            onExplain: { [weak self] in
                self?.handleAction(self?.onExplain)
            }
        ))
        Self.prepareHostingView(hostingView)

        if let panel {
            panel.contentView = hostingView
            positionBubble(panel: panel, at: mouseLocation, anchorRect: anchorRect, size: size)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
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
        PanelChromeMotion.animatePresent(panel: panel, to: panel.frame)
        panel.invalidateShadow()

        startOutsideEventMonitor()
        scheduleAutoDismiss()
    }

    func hide() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        stopOutsideEventMonitor()

        guard let panel else { return }

        PanelChromeMotion.animateDismiss(panel: panel) { [weak self] in
            self?.panel?.close()
            self?.panel = nil
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

    private func handleAction(_ action: (() -> Void)?) {
        autoDismissTask?.cancel()
        stopOutsideEventMonitor()
        panel?.close()
        panel = nil
        action?()
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

    private static func prepareHostingView<Content: View>(_ hostingView: NSHostingView<Content>) {
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
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

/// Compact dual-action pill near the selected text: translate + explain.
/// Translucent material chrome (Apple materials) — not a solid accent fill —
/// so it reads as floating UI that doesn't steal focus from the selection.
private struct SelectionBubbleBar: View {
    var onTranslate: () -> Void
    var onExplain: () -> Void

    @State private var isBarHovering = false
    @State private var appeared = false
    @Environment(\.colorScheme) private var colorScheme

    private static let outerPaddingH: CGFloat = 3
    private static let outerPaddingV: CGFloat = 2
    private static let dividerHeight: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            bubbleButton(
                systemName: "character.textbox",
                help: "翻译",
                action: onTranslate
            )
            Capsule(style: .continuous)
                .fill(AstryxColor.borderEmphasized.opacity(isBarHovering ? 0.9 : 0.55))
                .frame(width: 1, height: Self.dividerHeight)
                .accessibilityHidden(true)
            bubbleButton(
                systemName: "questionmark",
                help: "解释",
                action: onExplain
            )
        }
        .padding(.horizontal, Self.outerPaddingH)
        .padding(.vertical, Self.outerPaddingV)
        .background(bubbleMaterial)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(materialEdgeHighlight, lineWidth: 0.5)
        )
        // No SwiftUI drop shadow — the panel uses `hasShadow` so the silhouette
        // follows the capsule alpha instead of the rectangular window bounds.
        .scaleEffect(appeared || MotionPreference.reduceMotion ? 1.0 : 0.94)
        .opacity(appeared || MotionPreference.reduceMotion ? 1 : 0)
        .animation(AstryxMotion.quick, value: isBarHovering)
        .onHover { hovering in
            isBarHovering = hovering
        }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("WhyText 操作")
    }

    private var bubbleMaterial: some View {
        ZStack {
            if MotionPreference.reduceTransparency {
                Color(nsColor: .controlBackgroundColor)
            } else {
                // cornerStyle masks at CALayer — SwiftUI clipShape alone does not clip materials.
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    state: .active,
                    cornerStyle: .capsule
                )
                // Light fill keeps vibrancy text legible without stacking translucent layers.
                Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.28 : 0.55)
            }
        }
        .clipShape(Capsule(style: .continuous))
    }

    /// Bright top-edge catch light — materials read as thicker when lit at the rim.
    private var materialEdgeHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.white.opacity(0.55)
    }

    private func bubbleButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BubbleButtonLabel(systemName: systemName)
        }
        .buttonStyle(BubblePressButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Icon label with its own hover fill so each slot reads as a separate hit target.
private struct BubbleButtonLabel: View {
    let systemName: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AstryxColor.textPrimary)
            // Optical: SF Symbol questionmark sits slightly high; nudge down.
            .offset(y: systemName == "questionmark" ? 0.5 : 0)
            .frame(width: SelectionBubbleBarMetrics.buttonWidth, height: SelectionBubbleBarMetrics.buttonHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(AstryxColor.overlayHover.opacity(isHovering ? 1 : 0))
            )
            .contentShape(Capsule())
            .animation(AstryxMotion.quick, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private enum SelectionBubbleBarMetrics {
    static let buttonWidth: CGFloat = 36
    static let buttonHeight: CGFloat = 28
}

/// Scale-on-press — feedback on pointer-down, interruptible.
private struct BubblePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(AstryxMotion.press, value: configuration.isPressed)
    }
}

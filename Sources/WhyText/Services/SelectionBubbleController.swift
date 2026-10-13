import AppKit
import SwiftUI
import WhyTextCore

final class SelectionBubbleController: NSObject, NSWindowDelegate {
    var onTranslate: (() -> Void)?
    var onExplain: (() -> Void)?

    private var panel: NSPanel?
    private var outsideEventMonitor: Any?
    private var autoDismissTask: Task<Void, Never>?
    private var isHoverPaused = false

    func show(at mouseLocation: NSPoint, anchorRect: CGRect? = nil) {
        autoDismissTask?.cancel()
        isHoverPaused = false

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
        isHoverPaused = false
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

/// Compact dual-action bar near the selected text: translate + explain.
/// Translucent material chrome with the same tinted glyph tiles as the Settings
/// sidebar, so it reads as WhyText without stealing focus from the selection.
private struct SelectionBubbleBar: View {
    var onTranslate: () -> Void
    var onExplain: () -> Void
    var onHoverChange: (Bool) -> Void

    @State private var appeared = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            BubbleActionButton(
                title: L10n.t("翻译"),
                systemName: "character.bubble.fill",
                tint: Color(nsColor: .systemGreen),
                action: onTranslate
            )
            Rectangle()
                .fill(AstryxColor.border)
                .frame(width: 1, height: Metrics.dividerHeight)
                .accessibilityHidden(true)
            BubbleActionButton(
                title: L10n.t("解释"),
                systemName: "questionmark",
                tint: Color(nsColor: .systemOrange),
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
    /// Concentric with the button hover fill: radius = inner radius + padding.
    static let radius: CGFloat = 11
    static let padding: CGFloat = 4
    static let buttonRadius: CGFloat = 7
    static let spacing: CGFloat = 2
    static let dividerHeight: CGFloat = 16
    static let tileSize: CGFloat = 18
}

/// Tinted glyph tile + label, with its own hover fill so each action reads as a
/// separate target. Height stays ≥28pt and the whole slot is clickable.
private struct BubbleActionButton: View {
    let title: String
    let systemName: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.x1_5) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                    .overlay(
                        Image(systemName: systemName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AstryxColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, Spacing.x1_5)
            .padding(.trailing, Spacing.x2_5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                    .fill(AstryxColor.overlayHover.opacity(isHovering ? 1.6 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(BubblePressButtonStyle())
        .animation(AstryxMotion.quick, value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
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

import AppKit
import SwiftUI

/// A thin vertical scroll indicator with no track. It uses the overlay style whatever
/// System Settings → Appearance → "Show scroll bars" says, so it stays hidden until the
/// content scrolls and fades out again shortly after.
final class ThinScroller: NSScroller {
    private static let knobWidth: CGFloat = 4
    private static let inset: CGFloat = 3

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        knobWidth + inset * 2
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob).insetBy(dx: 0, dy: Self.inset)
        guard knob.height > 0 else { return }
        let bar = NSRect(x: bounds.maxX - Self.inset - Self.knobWidth, y: knob.minY, width: Self.knobWidth, height: knob.height)
        NSColor(AstryxColor.scrollerKnob).setFill()
        NSBezierPath(roundedRect: bar, xRadius: Self.knobWidth / 2, yRadius: Self.knobWidth / 2).fill()
    }
}

extension NSScrollView {
    /// Swaps in `ThinScroller` and the overlay style. Call again after the system's
    /// preferred scroller style changes, because NSScrollView resets its style then.
    func useThinScroller() {
        if !(verticalScroller is ThinScroller) {
            verticalScroller = ThinScroller()
        }
        scrollerStyle = .overlay
    }
}

extension View {
    /// Gives the enclosing SwiftUI `ScrollView` a `ThinScroller`. Apply to the scroll view's content.
    func thinScroller() -> some View {
        background(ThinScrollerInstaller())
    }
}

private struct ThinScrollerInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        private var styleObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, let scrollView = enclosingScrollView else { return }
            scrollView.useThinScroller()
            guard styleObserver == nil else { return }
            styleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak scrollView] _ in
                // NSScrollView resets its own style on this notification; apply ours after it.
                DispatchQueue.main.async { scrollView?.useThinScroller() }
            }
        }

        deinit {
            if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) }
        }
    }
}

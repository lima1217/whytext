import AppKit
import SwiftUI

// MARK: - Reusable surface modifiers

private struct HairlineBorder: ViewModifier {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 0.5

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AstryxColor.border, lineWidth: lineWidth)
        )
    }
}

/// Layered transparent shadows that adapt to any background — prefer over solid borders
/// for elevated cards and controls. Form inputs keep hairline borders for accessibility.
/// Dark mode uses a white ring only (depth shadows wash out on dark surfaces).
private struct ShadowBorder: ViewModifier {
    var cornerRadius: CGFloat
    var isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let ring = isHovered ? AstryxColor.outlineRingHover : AstryxColor.outlineRing
        if colorScheme == .dark {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(ring, lineWidth: 1)
                )
        } else {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(ring, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.06), radius: 1, y: 1)
                .shadow(color: Color.black.opacity(isHovered ? 0.06 : 0.04), radius: 2, y: 2)
        }
    }
}

private struct CardSurface: ViewModifier {
    var radius: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .modifier(ShadowBorder(cornerRadius: radius, isHovered: false))
    }
}

/// Expands the tappable region without changing the visible control size.
/// Desktop chrome targets ≥40×40; touch contexts should use 44.
private struct MinHitArea: ViewModifier {
    var size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

extension View {
    /// 1px hairline for layout separators and form field outlines (accessibility).
    func hairlineBorder(cornerRadius: CGFloat = Radius.element, lineWidth: CGFloat = 0.5) -> some View {
        modifier(HairlineBorder(cornerRadius: cornerRadius, lineWidth: lineWidth))
    }

    /// Elevated surface: fill + adaptive shadow-as-border (no solid stroke).
    func cardSurface(radius: CGFloat = Radius.card, fill: Color = Color(nsColor: .controlBackgroundColor)) -> some View {
        modifier(CardSurface(radius: radius, fill: fill))
    }

    /// Shadow-as-border for buttons and compact controls.
    func shadowBorder(cornerRadius: CGFloat = Radius.element, isHovered: Bool = false) -> some View {
        modifier(ShadowBorder(cornerRadius: cornerRadius, isHovered: isHovered))
    }

    /// Ensure interactive chrome meets a minimum hit target (default 40pt for desktop).
    func minHitArea(_ size: CGFloat = 40) -> some View {
        modifier(MinHitArea(size: size))
    }
}

// MARK: - Motion
// Apple fluid-interface defaults (WWDC Designing Fluid Interfaces):
// damping 1.0 = critically damped (no overshoot) for chrome that just appears;
// damping ~0.8 only when the gesture itself carried momentum (flick / throw).
// `response` is settle time in seconds — not a fixed duration.

enum AstryxMotion {
    /// Snappy feedback for hover / toggles — interruptible ease (CSS-transition equivalent).
    static let quick: Animation = .easeOut(duration: 0.15)
    /// Content transitions (state changes, panel content swap).
    static let smooth: Animation = .easeInOut(duration: 0.22)
    /// Soft exit — shorter than enter so focus moves forward.
    static let exit: Animation = .easeIn(duration: 0.15)
    /// Default UI spring: critically damped, response ~0.35 (move / reposition).
    static let spring: Animation = .spring(response: 0.35, dampingFraction: 1.0)
    /// Sheet / floating chrome present — snappier response, still no bounce.
    static let present: Animation = .spring(response: 0.32, dampingFraction: 1.0)
    /// Momentum / flick spring — slight overshoot only because velocity preceded it.
    static let momentum: Animation = .spring(response: 0.30, dampingFraction: 0.82)
    /// Icon swaps: critically damped, response 0.3.
    static let icon: Animation = .spring(response: 0.3, dampingFraction: 1.0)
    /// Press scale feedback — lives on pointer-down, not release.
    static let press: Animation = .easeOut(duration: 0.1)
}

/// Reads System Settings → Accessibility → Display preferences.
enum MotionPreference {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

extension Animation {
    /// Critically damped spring by default. Pass `damping: ~0.8` only for momentum handoff.
    static func astryxSpring(response: Double = 0.35, damping: Double = 1.0) -> Animation {
        .spring(response: response, dampingFraction: damping)
    }
}

// MARK: - Panel / bubble window animation helpers
// One motion language for floating chrome. Windows move and fade but never animate
// their size on the way in or out: resizing a window re-lays out its text every frame,
// so a "scale" made from frame changes reflows the words while they're read. Size
// changes (a streaming answer) get the same short curve, so the edge glides instead
// of jumping. Every animation can be retargeted or cancelled mid-flight.

enum PanelChromeMotion {
    static let presentDuration: TimeInterval = 0.24
    static let dismissDuration: TimeInterval = 0.16
    static let resizeDuration: TimeInterval = 0.16
    /// How far chrome slides as it appears or leaves, toward or away from its anchor.
    static let slideDistance: CGFloat = 6

    /// Fast out, settles without overshoot (a critically damped spring's shape).
    private static let settleCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
    private static let leaveCurve = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)

    /// Fades in at `finalFrame`'s size, moving from `startOrigin` (default: in place).
    /// Starting it on a half-dismissed window picks up from where that window is.
    static func present(
        panel: NSPanel,
        to finalFrame: NSRect,
        from startOrigin: NSPoint? = nil,
        completion: @escaping () -> Void = {}
    ) {
        let reduceMotion = MotionPreference.reduceMotion
        if !panel.isVisible {
            panel.alphaValue = 0
            let origin = reduceMotion ? finalFrame.origin : (startOrigin ?? finalFrame.origin)
            panel.setFrame(NSRect(origin: origin, size: finalFrame.size), display: false)
        }
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.18 : presentDuration
            ctx.timingFunction = settleCurve
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: completion)
    }

    /// Fades out while sliding by `offset`, at a constant size.
    static func dismiss(panel: NSPanel, offset: CGVector = .zero, completion: @escaping () -> Void) {
        let reduceMotion = MotionPreference.reduceMotion
        var frame = panel.frame
        if !reduceMotion {
            frame.origin.x += offset.dx
            frame.origin.y += offset.dy
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.14 : dismissDuration
            ctx.timingFunction = leaveCurve
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    /// Glides to a new frame; a new call retargets from wherever the last one is.
    static func resize(panel: NSPanel, to frame: NSRect) {
        guard !MotionPreference.reduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = resizeDuration
            ctx.timingFunction = settleCurve
            panel.animator().setFrame(frame, display: true)
        }
    }
}


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
// Symmetric enter/exit paths (Apple spatial consistency): if it scales in, it scales out.

enum PanelChromeMotion {
    /// Present scale for floating chrome (panel, bubble). Reduced motion → opacity only.
    static let presentScale: CGFloat = 0.94
    static let presentDuration: TimeInterval = 0.32
    static let dismissDuration: TimeInterval = 0.18

    static func animatePresent(panel: NSPanel, to finalFrame: NSRect) {
        if MotionPreference.reduceMotion {
            panel.setFrame(finalFrame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            return
        }

        let scale = presentScale
        let shrunkWidth = finalFrame.width * scale
        let shrunkHeight = finalFrame.height * scale
        let startFrame = NSRect(
            x: finalFrame.midX - shrunkWidth / 2,
            y: finalFrame.midY - shrunkHeight / 2,
            width: shrunkWidth,
            height: shrunkHeight
        )

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Critically damped spring approximation (response ≈ 0.32).
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = presentDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    static func animateDismiss(panel: NSPanel, completion: @escaping () -> Void) {
        if MotionPreference.reduceMotion {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: completion)
            return
        }

        let current = panel.frame
        let scale = presentScale
        let shrunkWidth = current.width * scale
        let shrunkHeight = current.height * scale
        let endFrame = NSRect(
            x: current.midX - shrunkWidth / 2,
            y: current.midY - shrunkHeight / 2,
            width: shrunkWidth,
            height: shrunkHeight
        )

        // Mirror the present curve (spatial consistency: leave the way you arrived).
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = dismissDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.8, 0.1)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: completion)
    }
}


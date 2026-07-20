import AppKit
import SwiftUI

// MARK: - Dynamic color helpers

extension NSColor {
    /// Parse a hex string into an opaque or alpha-blended `NSColor`.
    /// Accepts `#RGB`, `#RRGGBB`, or `#RRGGBBAA`. Does not adapt to appearance on its own;
    /// pair with `Color.dynamic(light:dark:)` for automatic light/dark switching.
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r, g, b, a: CGFloat
        switch cleaned.count {
        case 3: // #RGB → #RRGGBBFF
            r = CGFloat((rgb >> 8 & 0xF) * 17) / 255
            g = CGFloat((rgb >> 4 & 0xF) * 17) / 255
            b = CGFloat((rgb & 0xF) * 17) / 255
            a = 1
        case 6: // #RRGGBB
            r = CGFloat((rgb >> 16) & 0xFF) / 255
            g = CGFloat((rgb >> 8) & 0xFF) / 255
            b = CGFloat(rgb & 0xFF) / 255
            a = 1
        case 8: // #RRGGBBAA
            r = CGFloat((rgb >> 24) & 0xFF) / 255
            g = CGFloat((rgb >> 16) & 0xFF) / 255
            b = CGFloat((rgb >> 8) & 0xFF) / 255
            a = CGFloat(rgb & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }

        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

extension Color {
    /// A `Color` that resolves differently in light and dark appearances.
    /// The SwiftUI port of CSS `light-dark()`: the dynamic provider is evaluated on each draw,
    /// so the color tracks `System Settings → Appearance` without a re-launch.
    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil {
                return NSColor(hex: dark)
            }
            return NSColor(hex: light)
        })
    }
}

// MARK: - Semantic colors
// Values transplanted from `@astryxdesign/theme-neutral/dist/theme.css`.
// Windows and controls keep macOS semantic backgrounds (windowBackgroundColor etc.)
// because those carry vibrancy and automatic light/dark adaptation the hex values can't.

enum AstryxColor {
    // Text
    static let textPrimary = Color.dynamic(light: "#171717", dark: "#fafafa")
    static let textSecondary = Color.dynamic(light: "#737373", dark: "#a3a3a3")
    static let textDisabled = Color.dynamic(light: "#a3a3a3", dark: "#525252")

    // Borders
    static let border = Color.dynamic(light: "#ebebeb", dark: "#FFFFFF1A")
    static let borderEmphasized = Color.dynamic(light: "#d4d4d4", dark: "#525252")

    // Overlays / fills
    static let overlayHover = Color.dynamic(light: "#0000000D", dark: "#FFFFFF0D")
    static let overlayPressed = Color.dynamic(light: "#0000001A", dark: "#FFFFFF1A")

    // Status
    static let success = Color.dynamic(light: "#007004", dark: "#9fe59b")
    static let error = Color.dynamic(light: "#a50c25", dark: "#ffc6c1")
    static let warning = Color.dynamic(light: "#745b00", dark: "#fdcf4f")

    static let successMuted = Color.dynamic(light: "#c5e5c0", dark: "#84C9803D")
    static let errorMuted = Color.dynamic(light: "#facecb", dark: "#ff9e973D")
    static let warningMuted = Color.dynamic(light: "#f8da9d", dark: "#deb4333D")

    // Shadow tint
    static let shadow = Color.dynamic(light: "#0000001A", dark: "#0000004D")

    /// Pure black/white ring — never a tinted neutral (reads as dirt on the edge).
    static let outlineRing = Color.dynamic(light: "#0000001A", dark: "#FFFFFF1A")
    static let outlineRingHover = Color.dynamic(light: "#00000014", dark: "#FFFFFF21")
}

// MARK: - Spacing
// 4px base-unit scale mirroring Astryx `--spacing-*`.

enum Spacing {
    static let zero: CGFloat = 0
    static let half: CGFloat = 2
    static let x1: CGFloat = 4
    static let x1_5: CGFloat = 6
    static let x2: CGFloat = 8
    static let x2_5: CGFloat = 10
    static let x3: CGFloat = 12
    static let x3_5: CGFloat = 14
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x7: CGFloat = 28
    static let x8: CGFloat = 32
}

// MARK: - Radius
// Semantic scale: inner → element → container → page. `--radius-full` is expressed
// via `Capsule` rather than a numeric value.

enum Radius {
    static let none: CGFloat = 0
    static let inner: CGFloat = 4
    static let element: CGFloat = 8
    static let container: CGFloat = 12
    /// Card outer radius sized for ~16pt padding + `element` inner (16 + 8 = 24).
    static let card: CGFloat = 24
    static let page: CGFloat = 28

    /// Concentric radius: when a rounded container has padding, inner elements need a
    /// smaller radius to appear concentric with the outer corner. Ported from Astryx Card.
    /// When padding exceeds 24pt, layers read as separate surfaces — pick radii independently.
    static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - padding)
    }
}

// MARK: - Typography
// UI chrome fonts. Translation / explanation body size stays user-controlled
// (`translationFontSize`); its line-height and paragraph rhythm live in
// `MarkdownRenderer` (body ~1.55, paragraph spacing ~0.28× font size, single `\n`).

enum AstryxFont {
    static let caption = Font.system(size: 10)
    static let captionM = Font.system(size: 12)
    static let body = Font.system(size: 13)
    static let bodySemibold = Font.system(size: 13, weight: .semibold)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let bodyMono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let label = Font.system(size: 13, weight: .medium)
    static let heading3 = Font.system(size: 13, weight: .bold)
    static let heading4 = Font.system(size: 14, weight: .bold)
}

// MARK: - Type rhythm
// Tracking is size-specific (Apple UI Typography): small chrome gets a slight positive
// track; body stays near 0. Applied where we control Text directly.

enum TypeRhythm {
    /// Small uppercase section labels — positive tracking for legibility.
    static let sectionTracking: CGFloat = 0.4
}

// MARK: - Unified semantic tone
// Collapses the three duplicate tone definitions that existed across
// `StatusBadge.Tone`, `ProvidersSettingsView.statusColor`, and FloatingPanel inline colors.

enum Tone {
    case success
    case warning
    case neutral
    case danger

    var color: Color {
        switch self {
        case .success: AstryxColor.success
        case .warning: AstryxColor.warning
        case .neutral: AstryxColor.textSecondary
        case .danger: AstryxColor.error
        }
    }

    var mutedFill: Color {
        switch self {
        case .success: AstryxColor.successMuted
        case .warning: AstryxColor.warningMuted
        case .neutral: AstryxColor.overlayHover
        case .danger: AstryxColor.errorMuted
        }
    }

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .neutral: "circle.fill"
        case .danger: "xmark.circle.fill"
        }
    }
}

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

// MARK: - Contextual icon crossfade
// Keep both icons in the tree and cross-fade with opacity / scale / blur
// (scale 0.25→1, blur 4→0) so enter and exit both animate without a motion library.

struct ContextualIconSwap: View {
    var isActive: Bool
    var activeSystemName: String
    var inactiveSystemName: String
    var size: CGFloat = 14
    var weight: Font.Weight = .medium

    var body: some View {
        ZStack {
            Image(systemName: activeSystemName)
                .font(.system(size: size, weight: weight))
                .opacity(isActive ? 1 : 0)
                .scaleEffect(isActive ? 1 : 0.25)
                .blur(radius: isActive ? 0 : 4)

            Image(systemName: inactiveSystemName)
                .font(.system(size: size, weight: weight))
                .opacity(isActive ? 0 : 1)
                .scaleEffect(isActive ? 0.25 : 1)
                .blur(radius: isActive ? 4 : 0)
        }
        .animation(AstryxMotion.icon, value: isActive)
        .accessibilityHidden(true)
    }
}

// MARK: - Status dot
// A quiet, fill-less indicator for low-emphasis status rows. Use `StatusBadge` when
// a status needs to call attention to itself; use `StatusDot` when it should just read.

struct StatusDot: View {
    var tone: Tone
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
    }
}

// MARK: - Section label
// A small uppercase-ish label for grouping content inside a card.

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AstryxColor.textSecondary)
            .textCase(.uppercase)
            .tracking(TypeRhythm.sectionTracking)
    }
}

// MARK: - Quiet button style
// A restrained secondary control: transparent at rest, soft overlay on hover,
// shadow-as-border, scale-on-press. For high-frequency secondary actions.

struct QuietButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var cornerRadius: CGFloat = Radius.element
    var horizontalPadding: CGFloat = Spacing.x2_5
    var verticalPadding: CGFloat = Spacing.x1
    /// Disables press scale when motion would be distracting.
    var isStatic: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(
            configuration: configuration,
            tint: tint,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            isStatic: isStatic
        )
    }
}

/// Separate body so hover state can live alongside ButtonStyle's isPressed
/// (press feedback on pointer-down; hover fill for continuous tracking).
private struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var tint: Color?
    var cornerRadius: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var isStatic: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(AstryxFont.bodyMedium)
            .foregroundStyle(tint ?? AstryxColor.textSecondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .shadowBorder(cornerRadius: cornerRadius, isHovered: isHovering)
            .scaleEffect((!isStatic && configuration.isPressed) ? 0.96 : 1)
            .animation(AstryxMotion.press, value: configuration.isPressed)
            .animation(AstryxMotion.quick, value: isHovering)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovering = $0 }
    }

    private var fillColor: Color {
        if configuration.isPressed {
            return AstryxColor.overlayPressed
        }
        if isHovering {
            return AstryxColor.overlayHover
        }
        return Color.clear
    }
}

/// Icon-only chrome button with press scale (copy, visibility toggle, etc.).
struct QuietIconButtonStyle: ButtonStyle {
    var isStatic: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((!isStatic && configuration.isPressed) ? 0.96 : 1)
            .animation(AstryxMotion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    /// Quiet secondary button: shadow border + scale on press.
    static var quiet: QuietButtonStyle { QuietButtonStyle() }

    /// Quiet button with a custom foreground tint (e.g. accent, danger).
    static func quiet(tint: Color, isStatic: Bool = false) -> QuietButtonStyle {
        QuietButtonStyle(tint: tint, isStatic: isStatic)
    }

    /// Quiet button without press scale.
    static func quiet(isStatic: Bool) -> QuietButtonStyle {
        QuietButtonStyle(isStatic: isStatic)
    }
}

extension ButtonStyle where Self == QuietIconButtonStyle {
    static var quietIcon: QuietIconButtonStyle { QuietIconButtonStyle() }

    static func quietIcon(isStatic: Bool) -> QuietIconButtonStyle {
        QuietIconButtonStyle(isStatic: isStatic)
    }
}

extension View {
    /// Hover-reveal quiet button background. Apply to a `Button`'s label instead of
    /// a full ButtonStyle when you need custom content but want the same hover feel.
    func quietButtonHover(cornerRadius: CGFloat = Radius.element) -> some View {
        modifier(QuietButtonHover(cornerRadius: cornerRadius))
    }
}

private struct QuietButtonHover: ViewModifier {
    var cornerRadius: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AstryxColor.overlayHover)
                    .opacity(isHovering ? 1 : 0)
            )
            .onHover { isHovering = $0 }
            .animation(AstryxMotion.quick, value: isHovering)
    }
}

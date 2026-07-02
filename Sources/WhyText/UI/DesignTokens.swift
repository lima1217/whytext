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
    static let page: CGFloat = 28

    /// Concentric radius: when a rounded container has padding, inner elements need a
    /// smaller radius to appear concentric with the outer corner. Ported from Astryx Card.
    static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - padding)
    }
}

// MARK: - Typography
// UI chrome fonts. The translation body font stays user-controlled (`translationFontSize`)
// and is NOT routed through this scale — see `MarkdownTextView`.

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

private struct CardSurface: ViewModifier {
    var radius: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AstryxColor.border, lineWidth: 0.5)
            )
            .shadow(color: AstryxColor.shadow.opacity(0.6), radius: 1, y: 1)
    }
}

extension View {
    /// 1px Astryx hairline border. Replaces scattered `Color.primary.opacity(0.05~0.12)` strokes.
    func hairlineBorder(cornerRadius: CGFloat = Radius.element, lineWidth: CGFloat = 0.5) -> some View {
        modifier(HairlineBorder(cornerRadius: cornerRadius, lineWidth: lineWidth))
    }

    /// Card surface: rounded fill + hairline border + subtle shadow.
    /// `fill` defaults to the macOS control background so vibrancy is preserved.
    func cardSurface(radius: CGFloat = Radius.container, fill: Color = Color(nsColor: .controlBackgroundColor)) -> some View {
        modifier(CardSurface(radius: radius, fill: fill))
    }
}

// MARK: - Motion
// Unified animation rhythm. Replaces scattered magic durations across views.

enum AstryxMotion {
    /// Snappy feedback for hover / toggles.
    static let quick: Animation = .easeOut(duration: 0.16)
    /// Content transitions (state changes, panel content swap).
    static let smooth: Animation = .easeInOut(duration: 0.22)
    /// Spring for entrance / scale gestures.
    static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.8)
}

extension Animation {
    /// Convenience: a gentle spring matching `AstryxMotion.spring` with a tunable response.
    static func astryxSpring(response: Double = 0.35, damping: Double = 0.8) -> Animation {
        .spring(response: response, dampingFraction: damping)
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
            .tracking(0.3)
    }
}

// MARK: - Quiet button style
// A restrained secondary control: transparent at rest, soft overlay on hover,
// hairline border. For high-frequency secondary actions (copy, retry, paste, toggle).

struct QuietButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var cornerRadius: CGFloat = Radius.element
    var horizontalPadding: CGFloat = Spacing.x2_5
    var verticalPadding: CGFloat = Spacing.x1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AstryxFont.bodyMedium)
            .foregroundStyle(tint ?? AstryxColor.textSecondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? AstryxColor.overlayPressed : AstryxColor.overlayHover.opacity(0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AstryxColor.border, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    /// Quiet secondary button: transparent at rest, soft overlay on hover, hairline border.
    static var quiet: QuietButtonStyle { QuietButtonStyle() }

    /// Quiet button with a custom foreground tint (e.g. accent, danger).
    static func quiet(tint: Color) -> QuietButtonStyle { QuietButtonStyle(tint: tint) }
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

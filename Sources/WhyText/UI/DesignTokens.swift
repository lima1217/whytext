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


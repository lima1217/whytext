import AppKit
import SwiftUI

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

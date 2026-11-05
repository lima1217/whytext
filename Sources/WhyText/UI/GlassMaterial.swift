import AppKit
import SwiftUI

// MARK: - Glass material tokens
// Liquid glass for chrome that floats over other apps. A surface opts in by using
// these tokens for four things only — tint (background), filter (the scene behind),
// edges (inset/outer shadows) and ink (foreground + blend mode) — so its layout,
// spacing, radii and type stay what the design system already says.

/// Which recipe a surface uses. Decided from the theme and, when the scene behind
/// can be read, from that scene's luminance (`GlassState.resolve`).
enum GlassVariant: String, Equatable {
    /// Light theme: bright glass, dark ink. The default.
    case bright
    /// Light theme over a dark scene: smoky glass, light ink.
    case smoke
    /// Dark theme: dark glass, light ink.
    case dark

    var ink: GlassInk { self == .bright ? .dark : .light }

    var recipe: GlassRecipe {
        switch self {
        case .bright: .bright
        case .smoke: .smoke
        case .dark: .dark
        }
    }
}

struct GlassRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255) }
    /// Gamma-space luminance, 0…1 (same weights as the scene sampler).
    var luminance: Double { (0.299 * r + 0.587 * g + 0.114 * b) / 255 }

    func brightened(by factor: Double) -> GlassRGB {
        GlassRGB(min(255, r * factor), min(255, g * factor), min(255, b * factor))
    }
}

/// The material for one variant. Alphas are the tint's thin (sparse scene) and dense
/// (busy scene) ends; filter values follow CSS `blur() saturate() brightness()`.
struct GlassRecipe: Equatable {
    var tint: GlassRGB
    var thinAlpha: Double
    var denseAlpha: Double
    var blur: CGFloat
    var saturation: Double
    var brightness: Double

    static let bright = GlassRecipe(tint: GlassRGB(255, 255, 255), thinAlpha: 0.06, denseAlpha: 0.22, blur: 2, saturation: 1.8, brightness: 1.06)
    static let smoke = GlassRecipe(tint: GlassRGB(16, 18, 22), thinAlpha: 0.10, denseAlpha: 0.30, blur: 2, saturation: 1.7, brightness: 0.85)
    static let dark = GlassRecipe(tint: GlassRGB(20, 20, 24), thinAlpha: 0.16, denseAlpha: 0.38, blur: 2, saturation: 1.6, brightness: 0.8)
}

enum GlassMetrics {
    /// Tint alpha moves in fixed steps so neighbouring surfaces land on the same value.
    static let tintStep: Double = 0.04
    /// Hover lifts the tint's brightness instead of raising the shadow.
    static let hoverBrightening: Double = 1.14
    /// Edge lens: ~44pt wide on cards, `min(44, short side / 3.5)`, never under 4.
    static let lensEdgeWidth: CGFloat = 44
    static let lensMinEdgeWidth: CGFloat = 4
    /// Inward offset at the very edge, as a multiple of the edge width.
    static let lensEdgeOffset: CGFloat = 1.1
    /// Falloff exponent of `(1 - d / edge)`: hard fold at the rim, flat by the inner end.
    static let lensFalloff: CGFloat = 2.6
    /// Dispersion: red bends this much further, blue this much less.
    static let lensDispersion: CGFloat = 0.15
    /// Surfaces smaller than this skip the lens.
    static let lensMinSide: CGFloat = 32

    /// Corner radius macOS draws on a titled window (the result panel).
    static var windowCornerRadius: CGFloat {
        if #available(macOS 26.0, *) { return 16 }
        return 10
    }
}

// MARK: - Ink

enum GlassInk: String, Equatable {
    /// Dark text on bright glass.
    case dark
    /// Light text on smoky or dark glass.
    case light

    /// Text and icons pick up the glass beneath: multiply darkens into it,
    /// plus-lighter adds onto it.
    var blendMode: BlendMode { self == .dark ? .multiply : .plusLighter }

    /// Gamma-space luminance of primary ink, for density and contrast.
    var luminance: Double { self == .dark ? 0.14 : 0.94 }

    /// Opaque — the whole glyph is faded with `opacity`, so strokes and fills that
    /// overlap inside an icon don't darken where they cross.
    func color(_ level: GlassInkLevel) -> Color {
        switch (self, level) {
        case (.dark, .primary): Color.black
        case (.dark, .secondary): Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255)
        case (.light, .primary): Color.white
        case (.light, .secondary): Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255)
        }
    }

    func opacity(_ level: GlassInkLevel) -> Double {
        switch (self, level) {
        case (.dark, .primary): 0.86
        case (.dark, .secondary): 0.70
        case (.light, .primary): 0.94
        case (.light, .secondary): 0.64
        }
    }

    var appearance: NSAppearance? {
        NSAppearance(named: self == .dark ? .aqua : .darkAqua)
    }
}

enum GlassInkLevel {
    /// Headings, body, icons, progress.
    case primary
    /// Captions, hints, quiet icons.
    case secondary
}

// MARK: - Resolved state

/// Everything a glass surface needs to draw, after reading the scene behind it.
struct GlassState: Equatable {
    var variant: GlassVariant
    /// 0 = thin (sparse scene), 1 = dense (busy scene).
    var density: Double
    /// Multiplier on the filter's saturation so vivid scenes don't stain the glass.
    var keepSaturation: Double
    /// User setting, 0…1.5; 1 is the material as designed.
    var tintScale: Double
    /// Lowest tint alpha at which body text passes contrast over the scene.
    var contrastAlpha: Double = 0

    var ink: GlassInk { variant.ink }
    var recipe: GlassRecipe { variant.recipe }

    /// Tint alpha in `tintStep` steps between the recipe's thin and dense ends,
    /// raised to the contrast floor, then scaled by the user setting.
    var tintAlpha: Double {
        let r = recipe
        let raw = r.thinAlpha + (r.denseAlpha - r.thinAlpha) * min(max(density, 0), 1)
        let stepped = (raw / GlassMetrics.tintStep).rounded() * GlassMetrics.tintStep
        return min(1, max(stepped, contrastAlpha) * tintScale)
    }

    /// Below a tint scale of 1 the filter's lift thins with it; at 0 only blur,
    /// edges and shadow remain.
    var filterSaturation: Double {
        1 + (recipe.saturation * keepSaturation - 1) * min(tintScale, 1)
    }

    var filterBrightness: Double {
        1 + (recipe.brightness - 1) * min(tintScale, 1)
    }

    func tint(hovered: Bool) -> Color {
        let rgb = hovered ? recipe.tint.brightened(by: GlassMetrics.hoverBrightening) : recipe.tint
        // White can't get brighter, so bright glass thickens by one step instead.
        let alpha = hovered && variant == .bright ? tintAlpha + GlassMetrics.tintStep : tintAlpha
        return rgb.color.opacity(alpha)
    }

    /// The theme's own choice, with a dense tint — used when the scene can't be read.
    static func theme(dark: Bool, remembered: GlassVariant?, tintScale: Double) -> GlassState {
        let variant: GlassVariant = dark ? .dark : (remembered == .smoke ? .smoke : .bright)
        return GlassState(variant: variant, density: 1, keepSaturation: 1, tintScale: tintScale)
    }
}

private struct GlassStateKey: EnvironmentKey {
    static let defaultValue: GlassState? = nil
}

extension EnvironmentValues {
    /// The glass this view sits on, or nil on solid chrome (Settings).
    var glass: GlassState? {
        get { self[GlassStateKey.self] }
        set { self[GlassStateKey.self] = newValue }
    }
}

enum GlassAccessibility {
    /// Reduce Transparency or Increase Contrast: opaque surfaces in the same tint.
    static var prefersSolid: Bool {
        let workspace = NSWorkspace.shared
        return workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
    }
}

// MARK: - Edges and inner glow

/// One CSS `box-shadow: inset x y blur spread color`.
private struct GlassInset {
    var x: CGFloat
    var y: CGFloat
    var blur: CGFloat
    var spread: CGFloat
    var color: Color
}

private struct GlassEdgeSpec {
    var insets: [GlassInset]
    /// `inset 0 0 0 0.5px` — a hairline just inside the edge.
    var innerHairline: Color?
    /// `0 0 0 0.5px` — a hairline just outside (cards only; a window can't draw outside itself).
    var outerHairline: Color
    var dropColor: Color
    var dropRadius: CGFloat
    var dropY: CGFloat
    /// Radial highlight from the top-left: this alpha fading out by 55%.
    var radialHighlight: Double

    static func spec(for variant: GlassVariant) -> GlassEdgeSpec {
        switch variant {
        case .bright:
            GlassEdgeSpec(
                insets: [
                    GlassInset(x: 1.5, y: 1.5, blur: 1, spread: -1, color: .white.opacity(0.95)),
                    GlassInset(x: -1.5, y: -1.5, blur: 1, spread: -1, color: .white.opacity(0.55)),
                    // Inner glow: brighter along the top and left, a touch of shade at the bottom.
                    GlassInset(x: 2, y: 2, blur: 10, spread: 0, color: .white.opacity(0.30)),
                    GlassInset(x: 0, y: -2, blur: 8, spread: 0, color: .black.opacity(0.05)),
                ],
                innerHairline: .white.opacity(0.30),
                outerHairline: .black.opacity(0.06),
                dropColor: .black.opacity(0.08),
                dropRadius: 12,
                dropY: 6,
                radialHighlight: 0.30
            )
        case .smoke:
            GlassEdgeSpec(
                insets: [
                    GlassInset(x: 0, y: 1, blur: 0, spread: 0, color: .white.opacity(0.18)),
                ],
                innerHairline: nil,
                outerHairline: .black.opacity(0.28),
                dropColor: .black.opacity(0.14),
                dropRadius: 12,
                dropY: 6,
                radialHighlight: 0.08
            )
        case .dark:
            // About a third of the bright edges, with a deeper outline and shadow.
            GlassEdgeSpec(
                insets: [
                    GlassInset(x: 1.5, y: 1.5, blur: 1, spread: -1, color: .white.opacity(0.32)),
                    GlassInset(x: -1.5, y: -1.5, blur: 1, spread: -1, color: .white.opacity(0.18)),
                    GlassInset(x: 2, y: 2, blur: 10, spread: 0, color: .white.opacity(0.10)),
                    GlassInset(x: 0, y: -2, blur: 8, spread: 0, color: .black.opacity(0.12)),
                ],
                innerHairline: .white.opacity(0.10),
                outerHairline: .black.opacity(0.45),
                dropColor: .black.opacity(0.30),
                dropRadius: 12,
                dropY: 6,
                radialHighlight: 0.10
            )
        }
    }
}

/// Inset shadows, inner hairline and the radial highlight, drawn inside the shape.
private struct GlassEdgeLayer: View {
    var variant: GlassVariant
    var cornerRadius: CGFloat

    /// Room around the shape so shadows cast from just outside it have pixels to come from.
    private static let pad: CGFloat = 24

    var body: some View {
        let spec = GlassEdgeSpec.spec(for: variant)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let pad = Self.pad
        ZStack {
            GeometryReader { proxy in
                RadialGradient(
                    colors: [.white.opacity(spec.radialHighlight), .white.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: max(1, hypot(proxy.size.width, proxy.size.height) * 0.55)
                )
            }

            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: pad, dy: pad)
                context.clip(to: shape.path(in: rect))
                for inset in spec.insets {
                    var layer = context
                    layer.addFilter(.shadow(
                        color: inset.color,
                        radius: inset.blur / 2,
                        x: inset.x,
                        y: inset.y,
                        options: .shadowOnly
                    ))
                    // Everything outside the (spread-adjusted) shape casts the inset shadow.
                    var outside = Path(rect.insetBy(dx: -pad, dy: -pad))
                    outside.addPath(shape.inset(by: inset.spread).path(in: rect))
                    layer.fill(outside, with: .color(.black), style: FillStyle(eoFill: true))
                }
            }
            .padding(-pad)

            if let hairline = spec.innerHairline {
                shape.strokeBorder(hairline, lineWidth: 0.5)
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

/// The glass a whole window is made of: the refracted scene (or the system material
/// while none is available), the tint, then the edges.
struct GlassWindowBackground: View {
    @ObservedObject var backdrop: GlassBackdrop
    var cornerRadius: CGFloat
    var isHovered: Bool = false

    var body: some View {
        let state = backdrop.state
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if GlassAccessibility.prefersSolid {
                shape.fill(state.recipe.tint.color)
            } else {
                // Live blur underneath: shows while the scene is being (re)captured.
                VisualEffectView(
                    material: .popover,
                    blendingMode: .behindWindow,
                    state: .active,
                    cornerStyle: .continuous(cornerRadius)
                )
                if let lens = backdrop.lens {
                    Image(decorative: lens.image, scale: lens.scale)
                        .resizable()
                        .transition(.opacity)
                        .id(lens.id)
                }
                shape.fill(state.tint(hovered: isHovered))
                GlassEdgeLayer(variant: state.variant, cornerRadius: cornerRadius)
            }
        }
        .clipShape(shape)
        .animation(AstryxMotion.smooth, value: state)
        .animation(.easeOut(duration: 0.15), value: backdrop.lens?.id)
        .animation(AstryxMotion.quick, value: isHovered)
        .allowsHitTesting(false)
    }
}

/// A card sitting on window glass: a lighter layer of the same glass with its own
/// edges and drop shadow. Falls back to the given solid fill off glass.
private struct GlassCardBackground: View {
    var cornerRadius: CGFloat
    var solidFill: Color
    @Environment(\.glass) private var glass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let glass {
            let spec = GlassEdgeSpec.spec(for: glass.variant)
            ZStack {
                if GlassAccessibility.prefersSolid {
                    shape.fill(glass.recipe.tint.color)
                    shape.strokeBorder(spec.outerHairline, lineWidth: 0.5)
                } else {
                    shape
                        .fill(Self.layerFill(glass))
                        .shadow(color: spec.dropColor, radius: spec.dropRadius, y: spec.dropY)
                    GlassEdgeLayer(variant: glass.variant, cornerRadius: cornerRadius)
                    shape.inset(by: -0.5).strokeBorder(spec.outerHairline, lineWidth: 0.5)
                }
            }
            .animation(AstryxMotion.smooth, value: glass)
        } else {
            shape.fill(solidFill)
                .overlay(shape.stroke(AstryxColor.border, lineWidth: 0.5))
        }
    }

    private static func layerFill(_ glass: GlassState) -> Color {
        switch glass.variant {
        case .bright: .white.opacity(0.28)
        case .smoke: .white.opacity(0.07)
        case .dark: .white.opacity(0.05)
        }
    }
}

extension View {
    /// Draws in glass ink (opaque color faded by opacity, blended into the glass) when
    /// on glass; otherwise the design system's text color for that level.
    func glassInk(_ level: GlassInkLevel) -> some View {
        modifier(GlassInkModifier(level: level))
    }

    /// Glass ink unless `override` is set — accent, status and disabled colors keep
    /// their own color.
    @ViewBuilder
    func glassInk(_ level: GlassInkLevel, override: Color?) -> some View {
        if let override {
            foregroundStyle(override)
        } else {
            glassInk(level)
        }
    }

    /// A card on window glass. Off glass it keeps the solid fill and hairline.
    func glassCard(cornerRadius: CGFloat, solidFill: Color) -> some View {
        background(GlassCardBackground(cornerRadius: cornerRadius, solidFill: solidFill))
    }

    /// Hover / selected highlight that is a lighter layer of the glass, never a grey wash.
    func glassHighlight(cornerRadius: CGFloat, isHovered: Bool, isSelected: Bool = false) -> some View {
        background(GlassHighlight(cornerRadius: cornerRadius, isHovered: isHovered, isSelected: isSelected))
    }
}

private struct GlassInkModifier: ViewModifier {
    var level: GlassInkLevel
    @Environment(\.glass) private var glass

    func body(content: Content) -> some View {
        if let ink = glass?.ink {
            content
                .foregroundStyle(ink.color(level))
                .opacity(ink.opacity(level))
                .blendMode(ink.blendMode)
        } else {
            content.foregroundStyle(level == .primary ? AstryxColor.textPrimary : AstryxColor.textSecondary)
        }
    }
}

private struct GlassHighlight: View {
    var cornerRadius: CGFloat
    var isHovered: Bool
    var isSelected: Bool
    @Environment(\.glass) private var glass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let glass {
                if glass.variant == .bright {
                    shape.fill(Color.white.opacity(isSelected ? 0.76 : 0.42))
                    if isSelected {
                        shape.strokeBorder(Color.white, lineWidth: 0.5)
                    }
                } else {
                    shape.fill(Color.white.opacity(isSelected ? 0.18 : 0.10))
                }
            } else {
                shape.fill(isSelected ? AstryxColor.overlayPressed : AstryxColor.overlayHover)
            }
        }
        .opacity(isHovered || isSelected ? 1 : 0)
    }
}

/// Puts a backdrop's state into the environment for everything drawn on it.
struct GlassScope<Content: View>: View {
    @ObservedObject var backdrop: GlassBackdrop
    var content: Content

    init(backdrop: GlassBackdrop, @ViewBuilder content: () -> Content) {
        self.backdrop = backdrop
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.glass, backdrop.state)
            .environmentObject(backdrop)
    }
}

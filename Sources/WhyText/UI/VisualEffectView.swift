import AppKit
import SwiftUI

/// How to clip an `NSVisualEffectView`. SwiftUI `.clipShape` does **not** clip AppKit
/// materials — the blur still fills the rectangular view bounds and shows sharp corners.
enum VisualEffectCornerStyle: Equatable {
    case none
    /// Continuous rounded rect with a fixed radius.
    case continuous(CGFloat)
    /// Pill: radius = half the shorter side, updated in `layout()`.
    case capsule
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State
    var cornerStyle: VisualEffectCornerStyle

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        cornerStyle: VisualEffectCornerStyle = .none
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.cornerStyle = cornerStyle
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = LayerMaskedVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.cornerStyle = cornerStyle
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        (nsView as? LayerMaskedVisualEffectView)?.cornerStyle = cornerStyle
    }
}

/// Applies a CALayer corner mask so behind-window materials follow a rounded / capsule edge.
private final class LayerMaskedVisualEffectView: NSVisualEffectView {
    var cornerStyle: VisualEffectCornerStyle = .none {
        didSet {
            guard cornerStyle != oldValue else { return }
            applyCornerMask()
        }
    }

    override func layout() {
        super.layout()
        applyCornerMask()
    }

    private func applyCornerMask() {
        wantsLayer = true
        guard let layer else { return }

        switch cornerStyle {
        case .none:
            layer.cornerRadius = 0
            layer.masksToBounds = false
        case .continuous(let radius):
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
        case .capsule:
            layer.cornerRadius = min(bounds.width, bounds.height) / 2
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
        }
    }
}

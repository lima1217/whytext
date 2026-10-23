import CoreGraphics
import Foundation

/// Where the result panel sits next to the text it explains: beside the selection,
/// never over it, growing away from it as the answer streams in.
public struct PanelPlacement: Equatable, Sendable {
    public enum Growth: Equatable, Sendable {
        /// Below the selection; the top edge stays put and the panel grows downward.
        case down
        /// Above the selection; the bottom edge stays put and the panel grows upward.
        case up
    }

    public var growth: Growth
    /// The edge that stays fixed: the top for `.down`, the bottom for `.up`.
    public var fixedEdgeY: CGFloat
    /// The panel's preferred left edge (the selection's start).
    public var anchorX: CGFloat
    /// Room on screen in the growth direction, capped at the preferred maximum.
    public var maxHeight: CGFloat
    public var visibleFrame: CGRect

    /// Below rather than above unless below is cramped: text reads downward, so what
    /// comes after the selection matters less than what led up to it.
    public static func make(
        anchor: CGRect,
        visibleFrame: CGRect,
        preferredMaxHeight: CGFloat,
        comfortableHeight: CGFloat = 240,
        gap: CGFloat = 8,
        margin: CGFloat = 8
    ) -> PanelPlacement {
        let below = anchor.minY - gap - (visibleFrame.minY + margin)
        let above = (visibleFrame.maxY - margin) - (anchor.maxY + gap)
        let x = anchor.minX

        if below >= min(preferredMaxHeight, comfortableHeight) || (below >= above && below >= 120) {
            return PanelPlacement(growth: .down, fixedEdgeY: anchor.minY - gap, anchorX: x,
                                  maxHeight: min(preferredMaxHeight, below), visibleFrame: visibleFrame)
        }
        if above >= 120 {
            return PanelPlacement(growth: .up, fixedEdgeY: anchor.maxY + gap, anchorX: x,
                                  maxHeight: min(preferredMaxHeight, above), visibleFrame: visibleFrame)
        }
        // The selection fills the screen: no side is free, so hang from the top.
        return PanelPlacement(growth: .down, fixedEdgeY: visibleFrame.maxY - margin, anchorX: x,
                              maxHeight: min(preferredMaxHeight, visibleFrame.height - 2 * margin),
                              visibleFrame: visibleFrame)
    }

    /// The panel frame for a content size; the height is capped at `maxHeight`.
    public func frame(for size: CGSize) -> CGRect {
        let height = min(size.height, maxHeight)
        let width = min(size.width, visibleFrame.width)
        let x = min(max(anchorX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = growth == .down ? fixedEdgeY - height : fixedEdgeY
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The same growth direction, re-anchored to where the user dragged the panel,
    /// so later growth starts from there instead of snapping back.
    public func moved(to frame: CGRect, preferredMaxHeight: CGFloat, margin: CGFloat = 8) -> PanelPlacement {
        var placement = self
        placement.anchorX = frame.minX
        switch growth {
        case .down:
            placement.fixedEdgeY = frame.maxY
            placement.maxHeight = min(preferredMaxHeight, max(frame.height, frame.maxY - (visibleFrame.minY + margin)))
        case .up:
            placement.fixedEdgeY = frame.minY
            placement.maxHeight = min(preferredMaxHeight, max(frame.height, (visibleFrame.maxY - margin) - frame.minY))
        }
        return placement
    }

    /// Where a panel of `size` starts when it emerges from `source` (the selection
    /// bubble): its fixed edge and left side lined up with the source's.
    public func origin(for size: CGSize, emergingFrom source: CGRect) -> CGPoint {
        let height = min(size.height, maxHeight)
        let y = growth == .down ? source.maxY - height : source.minY
        return CGPoint(x: source.minX, y: y)
    }
}

/// Accessibility reports rectangles with a top-left origin on the primary screen;
/// AppKit windows use a bottom-left origin.
public enum AXGeometry {
    /// `rect` in AppKit coordinates, or nil when it lands on no screen. Some apps
    /// report already-flipped rectangles, so both readings are tried and the one
    /// nearer the pointer wins; the standard flip wins ties.
    public static func cocoaRect(
        fromAX rect: CGRect,
        primaryScreenHeight: CGFloat,
        screens: [CGRect],
        near point: CGPoint
    ) -> CGRect? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let flipped = CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
        let candidates = [flipped, rect].filter { candidate in
            screens.contains { $0.insetBy(dx: -80, dy: -80).intersects(candidate) }
        }
        return candidates.min { distance($0, point) < distance($1, point) }
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

import AppKit

/// Monochrome menu bar glyph: an auspicious cloud (祥云) drawn as one light outline.
/// Three lobes sit on a flat base; the base runs on past the left lobe and lifts
/// into a thinning tail, and a single curl turns inside the largest lobe.
enum MenuBarIcon {
    static let image: NSImage = {
        // Wider than tall: the cloud is a wide shape, and an 18pt square left it
        // only ~8pt high next to other menu bar icons.
        let image = NSImage(size: canvas, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WhyText"
        return image
    }()

    private typealias Lobe = (center: NSPoint, radius: CGFloat)
    // Left and right lobes rest on the base line (y = 6.6).
    private static let left: Lobe = (NSPoint(x: 6.6, y: 9.0), 2.4)
    private static let middle: Lobe = (NSPoint(x: 10.6, y: 10.7), 3.4)
    private static let right: Lobe = (NSPoint(x: 14.4, y: 8.6), 2.0)

    private static let canvas = NSSize(width: 22, height: 18)
    /// The artwork's bounds on its authoring grid (tail tip to right lobe, base to top).
    private static let artwork = NSRect(x: 1.0, y: 6.0, width: 16.0, height: 8.7)
    /// Grid units → points: the cloud fills the canvas width (~21pt × 11.6pt).
    private static let zoom: CGFloat = 1.33
    /// Stroke widths in final points, so enlarging the cloud doesn't thicken its lines.
    private static let lineWidth: CGFloat = 1.4 / zoom
    private static let curlWidth: CGFloat = 1.3 / zoom

    /// Coordinates are authored on a y-up grid; `artwork` is centered in `rect` at `zoom`.
    private static func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let scale = zoom * rect.height / canvas.height
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -artwork.midX, y: -artwork.midY)
        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Outline: up and over the three lobes, clockwise, then back along the base.
        let (l1, m1) = upperIntersection(left, middle)
        let (m2, r2) = upperIntersection(middle, right)
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: left.center.x, y: left.center.y - left.radius))
        outline.appendArc(withCenter: left.center, radius: left.radius, startAngle: 270, endAngle: l1, clockwise: true)
        outline.appendArc(withCenter: middle.center, radius: middle.radius, startAngle: m1, endAngle: m2, clockwise: true)
        outline.appendArc(withCenter: right.center, radius: right.radius, startAngle: r2, endAngle: -90, clockwise: true)
        outline.close()
        stroke(outline, width: lineWidth)

        // Curl inside the middle lobe, spiraling inward clockwise.
        stroke(polyline(spiral(center: NSPoint(x: 10.6, y: 10.5), from: 1.8, to: 0.35, startAngle: 210, sweep: -300)), width: curlWidth)

        // Tail: the base line continues left, thinning, and lifts at the end.
        tapered(
            bezier(NSPoint(x: 7.2, y: 6.6), NSPoint(x: 4.6, y: 6.6), NSPoint(x: 2.8, y: 6.6), NSPoint(x: 1.2, y: 8.2)),
            from: lineWidth, to: 0.3
        ).fill()
    }

    /// Angles (degrees) on `a` and on `b` of the higher of their two intersection points.
    private static func upperIntersection(_ a: Lobe, _ b: Lobe) -> (CGFloat, CGFloat) {
        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y, d = hypot(dx, dy)
        let along = (a.radius * a.radius - b.radius * b.radius + d * d) / (2 * d)
        let h = sqrt(max(0, a.radius * a.radius - along * along))
        let mx = a.center.x + along * dx / d, my = a.center.y + along * dy / d
        let p1 = NSPoint(x: mx - h * dy / d, y: my + h * dx / d)
        let p2 = NSPoint(x: mx + h * dy / d, y: my - h * dx / d)
        let p = p1.y > p2.y ? p1 : p2
        return (atan2(p.y - a.center.y, p.x - a.center.x) * 180 / .pi,
                atan2(p.y - b.center.y, p.x - b.center.x) * 180 / .pi)
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    // MARK: - Geometry helpers

    /// Points along a spiral whose radius changes linearly with the angle (degrees; + = counterclockwise).
    private static func spiral(center: NSPoint, from r0: CGFloat, to r1: CGFloat, startAngle: CGFloat, sweep: CGFloat, steps: Int = 60) -> [NSPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            let angle = (startAngle + sweep * t) * .pi / 180
            let r = r0 + (r1 - r0) * t
            return NSPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        }
    }

    private static func bezier(_ p0: NSPoint, _ c1: NSPoint, _ c2: NSPoint, _ p1: NSPoint, steps: Int = 40) -> [NSPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps), u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return NSPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
                           y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
        }
    }

    private static func polyline(_ points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        return path
    }

    /// A filled outline around `points` whose width goes from `w0` to `w1`.
    private static func tapered(_ points: [NSPoint], from w0: CGFloat, to w1: CGFloat) -> NSBezierPath {
        var left: [NSPoint] = [], right: [NSPoint] = []
        for i in points.indices {
            let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
            let length = max(0.0001, hypot(b.x - a.x, b.y - a.y))
            let nx = -(b.y - a.y) / length, ny = (b.x - a.x) / length
            let half = (w0 + (w1 - w0) * CGFloat(i) / CGFloat(points.count - 1)) / 2
            left.append(NSPoint(x: points[i].x + nx * half, y: points[i].y + ny * half))
            right.append(NSPoint(x: points[i].x - nx * half, y: points[i].y - ny * half))
        }
        let path = polyline(left)
        right.reversed().forEach { path.line(to: $0) }
        path.close()
        return path
    }
}

import AppKit

/// Monochrome menu bar glyph derived from the app icon: a crescent ring with a
/// large dot at the top-right and a small dot at the bottom-left.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WhyText"
        return image
    }()

    /// Coordinates are authored on an 18×18 grid (y-up) and scaled to `rect`.
    private static func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = rect.width / 18
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + (cx - radius) * scale,
                y: rect.minY + (cy - radius) * scale,
                width: radius * 2 * scale,
                height: radius * 2 * scale
            ))
        }

        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        NSColor.black.setFill()

        // Hole is pushed toward the top-right so the ring thickens at the bottom-left.
        let ring = circle(8.2, 8.6, 6.6)
        ring.append(circle(9.4, 9.6, 3.7))
        ring.windingRule = .evenOdd
        ring.fill()

        // Cut gaps around the dots so the shapes stay distinct at menu bar size.
        context.setBlendMode(.clear)
        circle(13.6, 13.6, 4.4).fill()
        circle(3.9, 3.9, 3.0).fill()
        context.setBlendMode(.normal)

        circle(13.6, 13.6, 3.2).fill()
        circle(3.9, 3.9, 2.0).fill()
    }
}

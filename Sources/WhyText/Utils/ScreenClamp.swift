import AppKit
import Foundation

enum ScreenClamp {
    static func clampedOrigin(near point: NSPoint, size: NSSize) -> NSPoint {
        positionedOrigin(near: point, size: size)
    }

    static func positionedOrigin(near point: NSPoint, size: NSSize, margin: CGFloat = 14) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Keep behavior predictable: always prefer right+up first.
        var x = point.x + margin
        var y = point.y + margin

        if x + size.width > frame.maxX {
            x = point.x - size.width - margin
        }
        if y + size.height > frame.maxY {
            y = point.y - size.height - margin
        }

        var origin = clamp(origin: NSPoint(x: x, y: y), size: size, frame: frame)
        var rect = NSRect(origin: origin, size: size)

        // If clamping overlaps cursor, try mirrored candidates.
        if rect.contains(point) {
            let mirroredX = clamp(
                origin: NSPoint(x: point.x - size.width - margin, y: y),
                size: size,
                frame: frame
            )
            let mirroredXRect = NSRect(origin: mirroredX, size: size)
            if !mirroredXRect.contains(point) {
                return mirroredX
            }

            let mirroredY = clamp(
                origin: NSPoint(x: x, y: point.y - size.height - margin),
                size: size,
                frame: frame
            )
            let mirroredYRect = NSRect(origin: mirroredY, size: size)
            if !mirroredYRect.contains(point) {
                return mirroredY
            }

            origin = clamp(
                origin: NSPoint(x: point.x + margin, y: point.y + margin + 8),
                size: size,
                frame: frame
            )
            rect = NSRect(origin: origin, size: size)

            if rect.contains(point) {
                origin.y = min(frame.maxY - size.height, origin.y + margin + 6)
            }
        }

        return origin
    }

    private static func clamp(origin: NSPoint, size: NSSize, frame: NSRect) -> NSPoint {
        var x = origin.x
        var y = origin.y

        x = min(max(x, frame.minX), frame.maxX - size.width)
        y = min(max(y, frame.minY), frame.maxY - size.height)

        return NSPoint(x: x, y: y)
    }
}

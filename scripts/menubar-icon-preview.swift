import AppKit

/// Draws the menu bar icon beside system status icons on mock light and dark menu
/// bars at 2x, so its size and weight can be judged against its real neighbours.
/// Run through scripts/menubar-icon-preview.sh, which compiles it with MenuBarIcon.swift.
@main
enum MenuBarIconPreview {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("usage: menubar-icon-preview <out.png>")
            exit(2)
        }
        var icons: [NSImage] = []
        #if PREVIOUS
        icons.append(PreviousMenuBarIcon.image)
        #endif
        icons.append(MenuBarIcon.image)

        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .regular)
        let neighbours = ["wifi", "battery.75percent", "magnifyingglass", "cloud"].compactMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        let light = bar(icons, neighbours, background: NSColor(white: 0.93, alpha: 1), foreground: NSColor(white: 0, alpha: 0.85))
        let dark = bar(icons, neighbours, background: NSColor(white: 0.15, alpha: 1), foreground: NSColor(white: 1, alpha: 0.9))

        let sheet = NSImage(size: NSSize(width: light.size.width, height: light.size.height * 2))
        sheet.lockFocus()
        dark.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
        light.draw(at: NSPoint(x: 0, y: light.size.height), from: .zero, operation: .copy, fraction: 1)
        sheet.unlockFocus()
        write(sheet, to: args[1], scale: 2)
        print("wrote \(args[1]) (top: light bar, bottom: dark bar; left to right: \(icons.count == 2 ? "previous, current" : "current"), then system icons)")
    }

    static func bar(_ icons: [NSImage], _ neighbours: [NSImage], background: NSColor, foreground: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 360, height: 24))
        image.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        var x: CGFloat = 12
        for (i, icon) in (icons + neighbours).enumerated() {
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                foreground.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: x, y: (24 - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            x += icon.size.width + (i == icons.count - 1 ? 26 : 14)
        }
        image.unlockFocus()
        return image
    }

    static func write(_ image: NSImage, to path: String, scale: CGFloat) {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}

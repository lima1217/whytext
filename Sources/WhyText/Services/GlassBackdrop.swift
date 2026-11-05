import AppKit
import Combine
import CoreImage
import ScreenCaptureKit
import SwiftUI

/// Reads the scene behind a glass window and turns it into what the glass draws:
/// the ink/density decision (`state`) and, for large surfaces, the filtered and
/// refracted scene (`lens`).
///
/// The scene is read with ScreenCaptureKit, only when Screen Recording is already
/// granted (screenshot OCR asks for it); this never prompts. Without it — or on
/// macOS 13 — the glass falls back to the system material with the theme's ink and
/// a dense tint.
@MainActor
final class GlassBackdrop: ObservableObject {
    enum Source {
        /// Sample (and refract) the screen under the window.
        case scene
        /// Theme ink and dense tint only — for short-lived chrome.
        case theme
    }

    struct Lens {
        let id: Int
        let image: CGImage
        let scale: CGFloat
    }

    @Published private(set) var state: GlassState
    @Published private(set) var lens: Lens?

    private let source: Source
    private let cornerRadius: CGFloat
    private let inkMemoryKey: String?
    private var tintScales: (light: Double, dark: Double) = (1, 1)

    private weak var window: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var tintScaleCancellable: AnyCancellable?
    private var refreshTimer: Timer?
    private var settleWorkItem: DispatchWorkItem?
    private var captureInFlight = false
    private var captureQueued = false
    private var lensSerial = 0
    /// Displacement field for the last size / radius / edge, reused until those change.
    private var lensMap: GlassLensMap?

    /// How long a window has to stay put before its scene is read again.
    private static let settleDelay: TimeInterval = 0.2
    /// Re-read a still window this often, so the glass follows a scene that scrolls.
    private static let refreshInterval: TimeInterval = 1.5

    init(source: Source, cornerRadius: CGFloat, inkMemoryKey: String? = nil) {
        self.source = source
        self.cornerRadius = cornerRadius
        self.inkMemoryKey = inkMemoryKey
        let remembered = inkMemoryKey
            .flatMap { UserDefaults.standard.string(forKey: $0) }
            .flatMap(GlassVariant.init(rawValue:))
        state = .theme(dark: Self.themeIsDark, remembered: remembered, tintScale: 1)

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.themeDidChange() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Follows the user's tint settings (light theme, dark theme).
    func bindTintScales<P: Publisher>(_ publisher: P) where P.Output == (Double, Double), P.Failure == Never {
        tintScaleCancellable = publisher
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] light, dark in
                guard let self else { return }
                tintScales = (light, dark)
                withAnimation(AstryxMotion.smooth) {
                    self.state.tintScale = self.currentTintScale
                }
                captureSoon()
            }
    }

    /// Starts reading the scene under `window` and keeps its appearance on the ink.
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        self.window = window
        applyWindowAppearance()

        guard source == .scene else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            windowObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.windowFrameDidChange() }
            })
        }
        windowObservers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.captureSoon() }
        })

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureNow() }
        }
        captureSoon()
    }

    // MARK: - Triggers

    private static var themeIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private var currentTintScale: Double {
        Self.themeIsDark ? tintScales.dark : tintScales.light
    }

    private func themeDidChange() {
        withAnimation(AstryxMotion.smooth) {
            state = .theme(dark: Self.themeIsDark, remembered: rememberedVariant, tintScale: currentTintScale)
        }
        applyWindowAppearance()
        captureSoon()
    }

    /// A moved or resized window no longer lines up with its captured scene: let the
    /// live material show until it settles and the scene is read again.
    private func windowFrameDidChange() {
        if lens != nil {
            lens = nil
        }
        captureSoon()
    }

    private func captureSoon() {
        guard source == .scene else { return }
        settleWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.captureNow() }
        }
        settleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: workItem)
    }

    // MARK: - Capture

    private func captureNow() {
        guard source == .scene, let window, window.isVisible, window.occlusionState.contains(.visible) else { return }
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess(), let screen = window.screen else {
            useTheme()
            return
        }
        guard !captureInFlight else {
            captureQueued = true
            return
        }
        captureInFlight = true

        let frame = window.frame
        let request = GlassSceneRequest(
            frame: frame,
            screenFrame: screen.frame,
            displayID: screen.displayID,
            scale: screen.backingScaleFactor,
            cornerRadius: cornerRadius,
            previous: state.variant,
            darkTheme: Self.themeIsDark,
            tintScale: currentTintScale,
            lensMap: lensMap
        )

        Task { [weak self] in
            let result = try? await GlassSceneRenderer.render(request)
            await MainActor.run {
                guard let self else { return }
                self.captureInFlight = false
                self.finishCapture(result, frame: frame)
                if self.captureQueued {
                    self.captureQueued = false
                    self.captureSoon()
                }
            }
        }
    }

    private func finishCapture(_ result: GlassSceneResult?, frame: NSRect) {
        guard let result else {
            useTheme()
            return
        }
        lensMap = result.lensMap ?? lensMap
        withAnimation(AstryxMotion.smooth) {
            state = result.state
        }
        rememberVariant(result.state.variant)
        applyWindowAppearance()

        // The window moved while we were reading it; that capture is stale.
        guard window?.frame == frame, let image = result.lensImage else { return }
        lensSerial += 1
        lens = Lens(id: lensSerial, image: image, scale: result.scale)
    }

    private func useTheme() {
        lens = nil
        let themed = GlassState.theme(dark: Self.themeIsDark, remembered: rememberedVariant, tintScale: currentTintScale)
        guard themed != state else { return }
        withAnimation(AstryxMotion.smooth) {
            state = themed
        }
        applyWindowAppearance()
    }

    // MARK: - Ink memory and appearance

    private var rememberedVariant: GlassVariant? {
        inkMemoryKey
            .flatMap { UserDefaults.standard.string(forKey: $0) }
            .flatMap(GlassVariant.init(rawValue:))
    }

    /// The next panel opens with the ink this one ended on.
    private func rememberVariant(_ variant: GlassVariant) {
        guard let inkMemoryKey, variant != .dark else { return }
        UserDefaults.standard.set(variant.rawValue, forKey: inkMemoryKey)
    }

    /// Dynamic colors and system controls follow the ink, not the system theme.
    private func applyWindowAppearance() {
        guard let window else { return }
        let appearance: NSAppearance? = source == .scene ? state.ink.appearance : nil
        if window.appearance?.name != appearance?.name {
            window.appearance = appearance
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}

// MARK: - Deciding ink and density

/// The scene behind a surface, from a 5 × 3 grid of points.
struct GlassSceneSample {
    /// Mean of the grid without its two darkest and two brightest points.
    var luminance: Double
    /// Brightest point minus darkest point.
    var texture: Double
    /// Mean colourfulness, (max − min channel) / 255.
    var chroma: Double
    var darkest: Double
    var brightest: Double
}

extension GlassState {
    /// Ink keeps its current side within ±0.05 of the 0.5 line, so a surface over a
    /// mid-grey scene doesn't flicker.
    static let inkHysteresis: Double = 0.05
    /// WCAG AA for body text.
    static let minimumContrast: Double = 4.5

    static func resolve(
        sample: GlassSceneSample,
        previous: GlassVariant,
        darkTheme: Bool,
        tintScale: Double
    ) -> GlassState {
        let variant: GlassVariant
        if darkTheme {
            variant = .dark
        } else {
            let line = 0.5 + (previous == .smoke ? inkHysteresis : -inkHysteresis)
            variant = sample.luminance < line ? .smoke : .bright
        }

        let ink = variant.ink
        let closeness = 1 - abs(sample.luminance - ink.luminance)
        let density = min(1, max(0, 0.55 * closeness + 0.7 * sample.texture + 0.3 * sample.chroma))
        let keepSaturation = max(0.45, 1 - 0.75 * sample.chroma)

        var state = GlassState(variant: variant, density: density, keepSaturation: keepSaturation, tintScale: tintScale)
        state.contrastAlpha = contrastAlpha(for: state, sample: sample)
        return state
    }

    /// Raises the tint (never the ink's transparency) until body text passes on the
    /// part of the scene that is worst for this ink, at the designed tint.
    private static func contrastAlpha(for state: GlassState, sample: GlassSceneSample) -> Double {
        let recipe = state.recipe
        let ink = state.ink
        let worst = ink == .dark ? sample.darkest : sample.brightest
        let scene = min(1, worst * recipe.brightness)
        var designed = state
        designed.tintScale = 1
        var alpha = designed.tintAlpha

        while alpha < 0.9 {
            let surface = (1 - alpha) * scene + alpha * recipe.tint.luminance
            // Multiply darkens into the surface; plus-lighter adds onto it.
            let text = ink == .dark
                ? surface * (1 - ink.opacity(.primary))
                : min(1, surface + ink.opacity(.primary))
            if contrastRatio(surface, text) >= minimumContrast { break }
            alpha += GlassMetrics.tintStep
        }
        return alpha
    }

    private static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        let la = linear(a), lb = linear(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}

// MARK: - Capture and render

struct GlassSceneRequest: Sendable {
    var frame: NSRect
    var screenFrame: NSRect
    var displayID: CGDirectDisplayID
    var scale: CGFloat
    var cornerRadius: CGFloat
    var previous: GlassVariant
    var darkTheme: Bool
    var tintScale: Double
    var lensMap: GlassLensMap?
}

struct GlassSceneResult: @unchecked Sendable {
    var state: GlassState
    var lensImage: CGImage?
    var lensMap: GlassLensMap?
    var scale: CGFloat
}

enum GlassSceneRenderer {
    enum Failure: Error {
        case unavailable
    }

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .cacheIntermediates: false,
    ])

    static func render(_ request: GlassSceneRequest) async throws -> GlassSceneResult {
        guard #available(macOS 14.0, *) else { throw Failure.unavailable }
        let capture = try await captureScene(request)

        return try await Task.detached(priority: .userInitiated) {
            try process(capture, request: request)
        }.value
    }

    /// Decides ink and density from the scene, then filters and refracts it.
    static func process(_ capture: Capture, request: GlassSceneRequest) throws -> GlassSceneResult {
        let sample = sample(capture.image)
        let state = GlassState.resolve(
            sample: sample,
            previous: request.previous,
            darkTheme: request.darkTheme,
            tintScale: request.tintScale
        )

        let size = request.frame.size
        guard min(size.width, size.height) >= GlassMetrics.lensMinSide else {
            return GlassSceneResult(state: state, lensImage: nil, lensMap: nil, scale: request.scale)
        }
        let width = Int((size.width * request.scale).rounded())
        let height = Int((size.height * request.scale).rounded())
        guard let filtered = filter(capture, width: width, height: height, state: state, scale: request.scale) else {
            throw Failure.unavailable
        }
        let map = GlassLensMap.reusing(
            request.lensMap,
            width: width,
            height: height,
            cornerRadius: request.cornerRadius * request.scale,
            edge: GlassLensMap.edgeWidth(for: size) * request.scale
        )
        let image = map.refract(filtered)
        return GlassSceneResult(state: state, lensImage: image, lensMap: map, scale: request.scale)
    }

    struct Capture: @unchecked Sendable {
        var image: CGImage
        /// Where the captured pixels sit inside the full surface, top-left origin, in pixels.
        /// Smaller than the surface when the window hangs off the display.
        var placement: CGRect
    }

    @available(macOS 14.0, *)
    private static func captureScene(_ request: GlassSceneRequest) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            throw Failure.unavailable
        }

        // Display-local, top-left origin, in points; clipped to the display.
        let screen = request.screenFrame
        let local = CGRect(
            x: request.frame.minX - screen.minX,
            y: screen.maxY - request.frame.maxY,
            width: request.frame.width,
            height: request.frame.height
        )
        let visible = local.intersection(CGRect(origin: .zero, size: screen.size))
        guard !visible.isEmpty else { throw Failure.unavailable }

        // Our own windows (panel, bubble) are what's being drawn — never what's behind.
        let pid = ProcessInfo.processInfo.processIdentifier
        let filter: SCContentFilter
        if let app = content.applications.first(where: { $0.processID == pid }) {
            filter = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        } else {
            let own = content.windows.filter { $0.owningApplication?.processID == pid }
            filter = SCContentFilter(display: display, excludingWindows: own)
        }

        let config = SCStreamConfiguration()
        config.sourceRect = visible
        config.width = Int((visible.width * request.scale).rounded())
        config.height = Int((visible.height * request.scale).rounded())
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let placement = CGRect(
            x: (visible.minX - local.minX) * request.scale,
            y: (visible.minY - local.minY) * request.scale,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        return Capture(image: image, placement: placement)
    }

    /// 5 × 3 points over the scene, each the average of a small patch.
    private static func sample(_ image: CGImage) -> GlassSceneSample {
        let columns = 5, rows = 3
        let width = columns * 8, height = rows * 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var points: [(luminance: Double, chroma: Double)] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let x = column * 8 + 4, y = row * 8 + 4
                let i = (y * width + x) * 4
                let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
                let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
                let chroma = (max(r, g, b) - min(r, g, b)) / 255
                points.append((luminance, chroma))
            }
        }
        points.sort { $0.luminance < $1.luminance }
        let trimmed = points.dropFirst(2).dropLast(2)
        let count = Double(trimmed.count)
        return GlassSceneSample(
            luminance: trimmed.reduce(0) { $0 + $1.luminance } / count,
            texture: points.last!.luminance - points.first!.luminance,
            chroma: trimmed.reduce(0) { $0 + $1.chroma } / count,
            darkest: points.first!.luminance,
            brightest: points.last!.luminance
        )
    }

    /// blur(2px) saturate() brightness(), over the full surface (edges clamped where
    /// the window hangs off the display).
    private static func filter(_ capture: Capture, width: Int, height: Int, state: GlassState, scale: CGFloat) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let b = state.filterBrightness
        let image = CIImage(cgImage: capture.image)
            .transformed(by: CGAffineTransform(
                translationX: capture.placement.minX,
                y: CGFloat(height) - capture.placement.maxY
            ))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(state.recipe.blur * scale))
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: state.filterSaturation,
                kCIInputBrightnessKey: 0,
                kCIInputContrastKey: 1,
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: b, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: b, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .cropped(to: full)
        return ciContext.createCGImage(image, from: full, format: .RGBA8, colorSpace: colorSpace)
    }
}

// MARK: - Edge lens

/// Where each pixel in the edge band samples from: a slab of glass whose rim folds
/// the scene back on itself and whose middle stays flat. Built once per size,
/// corner radius and edge width, then reused.
struct GlassLensMap: @unchecked Sendable {
    let width: Int
    let height: Int
    let cornerRadius: CGFloat
    let edge: CGFloat
    /// Pixel index and its inward sampling offset, for edge-band pixels only.
    private let indices: [Int32]
    private let dx: [Float]
    private let dy: [Float]

    static func edgeWidth(for size: CGSize) -> CGFloat {
        let short = min(size.width, size.height)
        return max(GlassMetrics.lensMinEdgeWidth, min(GlassMetrics.lensEdgeWidth, short / 3.5))
    }

    static func reusing(_ map: GlassLensMap?, width: Int, height: Int, cornerRadius: CGFloat, edge: CGFloat) -> GlassLensMap {
        if let map, map.width == width, map.height == height, map.cornerRadius == cornerRadius, map.edge == edge {
            return map
        }
        return GlassLensMap(width: width, height: height, cornerRadius: cornerRadius, edge: edge)
    }

    private init(width: Int, height: Int, cornerRadius: CGFloat, edge: CGFloat) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.edge = edge

        let halfW = Float(width) / 2, halfH = Float(height) / 2
        let edgeF = Float(edge)
        // Bend direction comes from a corner at least as round as the band is wide;
        // with the drawn (tighter) corner it would flip along the diagonal and crease.
        let radius = min(max(Float(cornerRadius), edgeF), min(halfW, halfH))
        let drawnRadius = min(Float(cornerRadius), min(halfW, halfH))
        let maxOffset = Float(GlassMetrics.lensEdgeOffset) * edgeF
        let falloff = Float(GlassMetrics.lensFalloff)

        var indices: [Int32] = []
        var dx: [Float] = []
        var dy: [Float] = []

        for y in 0..<height {
            let py = Float(y) + 0.5 - halfH
            // Rows deep inside only have band pixels near the left and right edges.
            for x in 0..<width {
                let px = Float(x) + 0.5 - halfW
                let qx = abs(px) - (halfW - radius)
                let qy = abs(py) - (halfH - radius)
                // Signed distance to the rounded rect (negative inside).
                let outside = hypotf(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius
                // Between the drawn corner and the rounder one, the rim folds at full strength.
                let depth = max(0, -outside)
                guard depth < edgeF, Self.isInside(px, py, halfW: halfW, halfH: halfH, radius: drawnRadius) else { continue }

                // Outward normal.
                var nx: Float = 0, ny: Float = 0
                if qx > 0, qy > 0 {
                    let length = hypotf(qx, qy)
                    nx = qx / length * (px < 0 ? -1 : 1)
                    ny = qy / length * (py < 0 ? -1 : 1)
                } else if qx > qy {
                    nx = px < 0 ? -1 : 1
                } else {
                    ny = py < 0 ? -1 : 1
                }

                let offset = maxOffset * powf(1 - depth / edgeF, falloff)
                indices.append(Int32(y * width + x))
                dx.append(-nx * offset)
                dy.append(-ny * offset)
            }
        }

        self.indices = indices
        self.dx = dx
        self.dy = dy
    }

    private static func isInside(_ px: Float, _ py: Float, halfW: Float, halfH: Float, radius: Float) -> Bool {
        let qx = abs(px) - (halfW - radius)
        let qy = abs(py) - (halfH - radius)
        return hypotf(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius <= 0.5
    }

    /// Bends the edge band, red 15% further and blue 15% less than green, each
    /// colour sampled in its own channel.
    func refract(_ image: CGImage) -> CGImage? {
        guard image.width == width, image.height == height else { return nil }
        let rowBytes = width * 4
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        var source = [UInt8](repeating: 0, count: rowBytes * height)
        let drawn = source.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: space, bitmapInfo: info) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var output = source
        let spread = Float(GlassMetrics.lensDispersion)
        let channelScale: [Float] = [1 + spread, 1, 1 - spread]
        let maxX = Float(width - 1), maxY = Float(height - 1)

        source.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                for n in 0..<indices.count {
                    let index = Int(indices[n])
                    let x = Float(index % width), y = Float(index / width)
                    for channel in 0..<3 {
                        let k = channelScale[channel]
                        let sx = min(max(x + dx[n] * k, 0), maxX)
                        let sy = min(max(y + dy[n] * k, 0), maxY)
                        let x0 = Int(sx), y0 = Int(sy)
                        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
                        let fx = sx - Float(x0), fy = sy - Float(y0)
                        let a = Float(src[(y0 * width + x0) * 4 + channel])
                        let b = Float(src[(y0 * width + x1) * 4 + channel])
                        let c = Float(src[(y1 * width + x0) * 4 + channel])
                        let d = Float(src[(y1 * width + x1) * 4 + channel])
                        let top = a + (b - a) * fx
                        let bottom = c + (d - c) * fx
                        dst[index * 4 + channel] = UInt8(min(255, max(0, top + (bottom - top) * fy + 0.5)))
                    }
                }
            }
        }

        return output.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: space, bitmapInfo: info)?.makeImage()
        }
    }
}

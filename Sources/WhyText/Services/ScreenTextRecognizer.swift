import AppKit
import Foundation
import ImageIO
import Vision
import WhyTextCore

/// Lets the user drag out a screen region, then reads the text in it on-device.
///
/// Region selection is macOS's own `screencapture -i` (crosshair, Space for window
/// mode, Esc to cancel), so there's no custom overlay to maintain. Recognition uses
/// Vision; nothing leaves the Mac until the text is translated.
final class ScreenTextRecognizer {
    enum RecognitionError: LocalizedError {
        case permissionDenied
        case captureFailed
        case noText

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                L10n.t("截图识别需要「屏幕录制」权限。请在「系统设置 → 隐私与安全性 → 屏幕与系统录音」中允许 WhyText，然后重启 WhyText。")
            case .captureFailed:
                L10n.t("截图失败，请重试。")
            case .noText:
                L10n.t("截图里没有识别到文字。")
            }
        }
    }

    static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    /// Returns nil when the user cancels the selection.
    func captureAndRecognize(preferred: [TranslationLanguage]) async throws -> String? {
        // Without the permission, captures silently contain only the wallpaper.
        guard CGPreflightScreenCaptureAccess() else {
            // Shows the system prompt the first time; later calls are no-ops.
            CGRequestScreenCaptureAccess()
            throw RecognitionError.permissionDenied
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whytext-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try await runInteractiveCapture(to: fileURL)

        // Esc leaves no file behind.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RecognitionError.captureFailed
        }

        let text = try await Task.detached(priority: .userInitiated) {
            try Self.recognizeText(in: image, preferred: preferred)
        }.value

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecognitionError.noText
        }
        return text
    }

    private func runInteractiveCapture(to fileURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive region (Space toggles window mode), -x no shutter sound.
        process.arguments = ["-i", "-x", fileURL.path]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: RecognitionError.captureFailed)
            }
        }
    }

    private static func recognizeText(in image: CGImage, preferred: [TranslationLanguage]) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        // Order matters when scripts are ambiguous (e.g. kanji vs. hanzi): the
        // user's languages first, then everything else Vision supports.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let preferredCodes = preferred.map(\.visionLanguageCode).filter(supported.contains)
        request.recognitionLanguages = preferredCodes + supported.filter { !preferredCodes.contains($0) }

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let lines = (request.results ?? []).compactMap { observation -> OCRTextLayout.Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox // normalized, origin bottom-left
            return OCRTextLayout.Line(
                text: candidate.string,
                minX: box.minX,
                top: 1 - box.maxY,
                maxX: box.maxX,
                bottom: 1 - box.minY
            )
        }
        return OCRTextLayout.join(lines)
    }
}

private extension TranslationLanguage {
    var visionLanguageCode: String {
        switch self {
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .english: "en-US"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .spanish: "es-ES"
        case .russian: "ru-RU"
        }
    }
}

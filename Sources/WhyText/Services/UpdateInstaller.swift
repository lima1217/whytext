import AppKit
import Foundation
import Security
import WhyTextCore

/// Downloads a release zip, checks it, swaps it in for the running app, and relaunches.
///
/// The app downloads the zip itself, so it carries no quarantine flag and Gatekeeper
/// doesn't block the relaunch even though builds aren't notarized. In exchange,
/// the update must pass the checks Gatekeeper would otherwise stand in for: same
/// bundle ID, the advertised version, and a signature that satisfies the running
/// app's designated requirement — i.e. signed with the same certificate.
final class UpdateInstaller {
    enum InstallError: LocalizedError {
        case notInstallableInPlace
        case unstableSignature
        case downloadFailed(Int?)
        case unzipFailed
        case appNotFound
        case bundleMismatch
        case versionMismatch
        case signatureMismatch

        var errorDescription: String? {
            switch self {
            case .notInstallableInPlace:
                L10n.t("无法在原位置更新（例如 App 不在可写的位置）。请前往下载页手动更新。")
            case .unstableSignature:
                L10n.t("当前版本没有稳定的签名，无法自动更新。请前往下载页手动更新。")
            case .downloadFailed(let status):
                status.map { L10n.f("下载失败（HTTP %@）", String($0)) } ?? L10n.t("下载失败，请检查网络后重试。")
            case .unzipFailed:
                L10n.t("解压更新包失败。")
            case .appNotFound:
                L10n.t("更新包里没有找到 WhyText.app。")
            case .bundleMismatch, .versionMismatch:
                L10n.t("更新包与这个版本的发布信息不一致，已拒绝安装。")
            case .signatureMismatch:
                L10n.t("更新包的签名与当前 App 不一致，已拒绝安装。")
            }
        }
    }

    private var currentBundleURL: URL { Bundle.main.bundleURL }

    /// Whether this copy can replace itself: a real .app (not translocated by
    /// Gatekeeper) in a folder the user can write to.
    var canInstallInPlace: Bool {
        let bundle = currentBundleURL
        guard bundle.pathExtension == "app",
              !bundle.path.contains("/AppTranslocation/") else {
            return false
        }
        let fileManager = FileManager.default
        return fileManager.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
            && fileManager.isWritableFile(atPath: bundle.path)
    }

    /// Downloads and installs `version` from `downloadURL`. On success the new app is
    /// in place; call `relaunch()` to finish.
    func install(
        version: SemanticVersion,
        from downloadURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard canInstallInPlace else { throw InstallError.notInstallableInPlace }
        let requirement = try currentDesignatedRequirement()

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whytext-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let zipURL = workDirectory.appendingPathComponent("update.zip")
        try await download(downloadURL, to: zipURL, onProgress: onProgress)

        let currentBundleURL = currentBundleURL
        let newApp = try await Task.detached(priority: .userInitiated) {
            let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extracted.path], failure: InstallError.unzipFailed)

            guard let app = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                throw InstallError.appNotFound
            }
            try Self.verify(app, expectedVersion: version, requirement: requirement)
            // Belt and braces: our own download isn't quarantined, but never carry a flag over.
            try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path], failure: InstallError.unzipFailed)
            return app
        }.value

        // Swapping the bundle under a running process is fine on macOS: the old
        // executable stays mapped until we quit.
        _ = try FileManager.default.replaceItemAt(currentBundleURL, withItemAt: newApp)
    }

    /// Quits, then reopens the app at its path once this process is gone.
    @MainActor
    func relaunch() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n \"$1\"",
            "sh",
            currentBundleURL.path,
        ]
        try? helper.run()
        NSApp.terminate(nil)
    }

    // MARK: - Checks

    private func currentDesignatedRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else {
            throw InstallError.unstableSignature
        }

        // An ad-hoc signature's requirement pins this exact build's hash, which no
        // other build can satisfy.
        var text: CFString?
        SecRequirementCopyString(requirement, [], &text)
        if let text, (text as String).contains("cdhash") {
            throw InstallError.unstableSignature
        }
        return requirement
    }

    private static func verify(_ app: URL, expectedVersion: SemanticVersion, requirement: SecRequirement) throws {
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw InstallError.bundleMismatch
        }
        guard let version = (info["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init),
              version == expectedVersion else {
            throw InstallError.versionMismatch
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw InstallError.signatureMismatch
        }
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(
            kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        ))
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw InstallError.signatureMismatch
        }
    }

    // MARK: - Plumbing

    private static func run(_ tool: String, _ arguments: [String], failure: Error) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure }
    }

    private func download(_ url: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = DownloadDelegate(destination: destination, onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let onProgress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this returns, so move it now.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        guard status == 200 else {
            failure = UpdateInstaller.InstallError.downloadFailed(status)
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = error.map { _ in UpdateInstaller.InstallError.downloadFailed(nil) } ?? failure
        if let result {
            continuation?.resume(throwing: result)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

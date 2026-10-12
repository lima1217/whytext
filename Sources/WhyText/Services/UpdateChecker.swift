import AppKit
import Foundation
import WhyTextCore

/// Compares the running version with the latest GitHub release and, on request,
/// installs it in place (see `UpdateInstaller`). Nothing is installed without a click.
@MainActor
final class UpdateChecker: ObservableObject {
    struct AvailableUpdate: Equatable {
        var version: SemanticVersion
        var pageURL: URL
        /// The release's `WhyText-<version>-mac.zip`, if it has one.
        var downloadURL: URL?
    }

    enum InstallState: Equatable {
        case idle
        case downloading(Double)
        case installing
        case failed(String)
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case failed(String)
    }

    static let releasesPageURL = URL(string: "https://github.com/lima1217/whytext/releases")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/lima1217/whytext/releases/latest")!
    private static let automaticInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var installState: InstallState = .idle

    /// Nil for unbundled development builds, which never check automatically.
    let currentVersion: SemanticVersion? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        .flatMap(SemanticVersion.init)

    private let session: URLSession
    private let installer = UpdateInstaller()
    private var timer: Timer?

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Checks shortly after launch, then once a day while the app runs.
    func setAutomaticChecks(enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled, currentVersion != nil else { return }

        // Don't compete with launch work or a first translation.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await self?.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.automaticInterval, repeats: true) { [weak self] _ in
            Task { await self?.check() }
        }
    }

    func check() async {
        guard status != .checking else { return }
        guard let currentVersion else {
            status = .failed(L10n.t("开发版本没有版本号，无法比较"))
            return
        }

        status = .checking
        do {
            let release = try await fetchLatestRelease()
            lastCheckedAt = Date()
            if let latest = SemanticVersion(release.tag_name), latest > currentVersion {
                let asset = release.assets.first { $0.name.hasPrefix("WhyText-") && $0.name.hasSuffix("-mac.zip") }
                availableUpdate = AvailableUpdate(
                    version: latest,
                    pageURL: release.html_url,
                    downloadURL: asset?.browser_download_url
                )
                status = .updateAvailable
            } else {
                availableUpdate = nil
                status = .upToDate
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(availableUpdate?.pageURL ?? Self.releasesPageURL)
    }

    /// Whether the available update can be installed with one click; otherwise the
    /// UI offers the download page.
    var canInstallUpdate: Bool {
        availableUpdate?.downloadURL != nil && installer.canInstallInPlace
    }

    var isInstalling: Bool {
        switch installState {
        case .downloading, .installing: true
        case .idle, .failed: false
        }
    }

    /// Downloads, verifies, and installs the available update, then relaunches.
    func installUpdate() {
        guard !isInstalling, let update = availableUpdate else { return }
        guard let downloadURL = update.downloadURL, installer.canInstallInPlace else {
            openDownloadPage()
            return
        }

        installState = .downloading(0)
        Task {
            do {
                try await installer.install(version: update.version, from: downloadURL) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.installState else { return }
                        self.installState = fraction >= 1 ? .installing : .downloading(fraction)
                    }
                }
                installState = .installing
                installer.relaunch()
            } catch {
                installState = .failed(error.localizedDescription)
            }
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var browser_download_url: URL
        }

        var tag_name: String
        var html_url: URL
        var assets: [Asset]
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw NSError(
                domain: "WhyText.UpdateChecker",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: L10n.f("GitHub 返回 HTTP %@", String(http.statusCode))]
            )
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}

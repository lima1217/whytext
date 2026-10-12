import AppKit
import Foundation
import WhyTextCore

/// Compares the running version with the latest GitHub release. It only tells the
/// user; downloading and installing stay manual (the app isn't notarized, so a
/// silent self-update would trip Gatekeeper anyway).
@MainActor
final class UpdateChecker: ObservableObject {
    struct AvailableUpdate: Equatable {
        var version: SemanticVersion
        var pageURL: URL
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

    /// Nil for unbundled development builds, which never check automatically.
    let currentVersion: SemanticVersion? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        .flatMap(SemanticVersion.init)

    private let session: URLSession
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
            status = .failed("开发版本没有版本号，无法比较")
            return
        }

        status = .checking
        do {
            let release = try await fetchLatestRelease()
            lastCheckedAt = Date()
            if let latest = SemanticVersion(release.tag_name), latest > currentVersion {
                availableUpdate = AvailableUpdate(version: latest, pageURL: release.html_url)
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

    private struct Release: Decodable {
        var tag_name: String
        var html_url: URL
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
                userInfo: [NSLocalizedDescriptionKey: "GitHub 返回 HTTP \(http.statusCode)"]
            )
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}

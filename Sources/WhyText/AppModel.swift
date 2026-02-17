import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var panelState = PanelState()

    var settingsStore: SettingsStore
    var historyStore: HistoryStore

    private let selectionService: AccessibilitySelectionService
    private let selectionReader: SelectionReader
    private let llmClient: LLMClient
    private let promptRunner: PromptRunner
    private let panelController: FloatingPanelController
    private let selectionBubbleController: SelectionBubbleController
    private let hotKeyManager: HotKeyManager
    private let settingsWindowController: SettingsWindowController

    private var cancellables = Set<AnyCancellable>()
    private var runningTask: Task<Void, Never>?

    private var selectionMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseDownLocation: NSPoint?
    private var lastAutoPopupText: String = ""
    private var lastAutoPopupAt = Date.distantPast
    private var pendingSelectionText: String = ""
    private var suppressAutoPopupUntil = Date.distantPast

    init(
        settingsStore: SettingsStore = SettingsStore(),
        historyStore: HistoryStore = HistoryStore(),
        selectionService: AccessibilitySelectionService = AccessibilitySelectionService(),
        selectionReader: SelectionReader = SelectionReader(),
        llmClient: LLMClient = LLMClient(),
        panelController: FloatingPanelController = FloatingPanelController(),
        selectionBubbleController: SelectionBubbleController = SelectionBubbleController()
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.selectionService = selectionService
        self.selectionReader = selectionReader
        self.llmClient = llmClient
        self.promptRunner = PromptRunner(llmClient: llmClient)
        self.panelController = panelController
        self.selectionBubbleController = selectionBubbleController
        self.settingsWindowController = SettingsWindowController()

        self.hotKeyManager = HotKeyManager()

        settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        historyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settingsStore.$autoPopupOnSelection
            .sink { [weak self] enabled in
                self?.updateSelectionMonitor(enabled)
            }
            .store(in: &cancellables)

        updateSelectionMonitor(settingsStore.autoPopupOnSelection)

        settingsStore.$hotKeyShortcut
            .sink { [weak self] shortcut in
                self?.updateHotKeyRegistration(shortcut)
            }
            .store(in: &cancellables)

        updateHotKeyRegistration(settingsStore.hotKeyShortcut)
        hotKeyManager.onPressed = { [weak self] in
            Task { @MainActor in
                self?.openPanelFromHotKey()
            }
        }

        self.selectionBubbleController.onTap = { [weak self] in
            Task { @MainActor in
                self?.openPanelFromSelectionBubble()
            }
        }

        self.panelController.onDidClose = { [weak self] in
            Task { @MainActor in
                self?.handlePanelDidClose()
            }
        }
    }

    func openPanelFromMenu() {
        openPanelFromHotKey()
    }

    func openSettingsWindow() {
        settingsWindowController.show {
            SettingsView()
                .environmentObject(self)
        }
    }

    func requestAccessibilityPermissionPrompt() {
        selectionService.requestPermissionPrompt()
    }

    func relaunchApp() {
        let appURL = Bundle.main.bundleURL

        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [appURL.path]
        try? task.run()

        NSApp.terminate(nil)
    }

    func openPanelFromHotKey() {
        Task { @MainActor in
            await openPanelFlow()
        }
    }

    private func openPanelFromSelectionBubble() {
        selectionBubbleController.hide()

        let selectedText = sanitizeSelectedText(pendingSelectionText)
        guard !selectedText.isEmpty else { return }

        runningTask?.cancel()
        panelState = PanelState()
        panelState.phase = .choose
        panelState.selectedText = selectedText

        let point = NSEvent.mouseLocation
        panelController.show(at: point) {
            FloatingPanelView()
                .environmentObject(self)
        }

        run(action: .translate)
    }

    private func openPanelFlow() async {
        selectionBubbleController.hide()
        runningTask?.cancel()
        panelState = PanelState()
        panelState.phase = .choose
        panelState.isLoading = true

        let point = NSEvent.mouseLocation

        panelController.show(at: point) {
            FloatingPanelView()
                .environmentObject(self)
        }

        let feedbackStart = Date()

        var selectedText: String = ""
        var selectionError: String?

        do {
            let selection = try await selectionReader.readSelectedText()
            selectedText = sanitizeSelectedText(selection.text)
        } catch {
            selectionError = userFacingErrorMessage(for: error)
        }

        let minimumFeedback: TimeInterval = 0.2
        let elapsed = Date().timeIntervalSince(feedbackStart)
        if elapsed < minimumFeedback {
            try? await Task.sleep(nanoseconds: UInt64((minimumFeedback - elapsed) * 1_000_000_000))
        }

        guard panelController.isVisible else { return }

        if let selectionError {
            panelState.isLoading = false
            panelState.noticeMessage = nil
            panelState.errorMessage = selectionError
            return
        }

        let trimmed = sanitizeSelectedText(selectedText)
        guard !trimmed.isEmpty else {
            panelState.isLoading = false
            panelState.noticeMessage = nil
            panelState.errorMessage = "未读取到选中文本"
            return
        }

        panelState.selectedText = trimmed
        run(action: .translate)
    }

    func closePanel() {
        runningTask?.cancel()
        panelController.close()
    }

    func copyResultToPasteboard() {
        guard !panelState.resultText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(panelState.resultText, forType: .string)
    }

    func copyResultPlainTextToPasteboard() {
        guard !panelState.resultText.isEmpty else { return }
        let plain = MarkdownRenderer.plainText(panelState.resultText)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
    }

    func run(action: PanelAction) {
        guard let preflight = preflightForTranslation() else {
            return
        }

        let provider = preflight.provider
        let apiKey = preflight.apiKey
        let selectedText = preflight.selectedText

        panelState.lastAction = action
        panelState.lastInputText = selectedText
        panelState.phase = .result

        let template = settingsStore.translatePromptTemplate

        panelState.errorMessage = nil
        panelState.noticeMessage = nil
        panelState.isLoading = true
        panelState.resultText = ""

        runningTask?.cancel()
        runningTask = Task {
            do {
                let chunking = TextChunker.chunk(
                    text: selectedText,
                    maxCharacters: settingsStore.maxInputCharacters,
                    splitLongInput: settingsStore.splitLongInput
                )

                if chunking.wasTruncated {
                    await MainActor.run {
                        self.panelState.noticeMessage = "输入过长，已截断到 \(settingsStore.maxInputCharacters) 字符"
                    }
                } else if selectedText.count > settingsStore.maxInputCharacters && chunking.chunks.count > 1 {
                    await MainActor.run {
                        self.panelState.noticeMessage = "输入过长，已分 \(chunking.chunks.count) 段处理"
                    }
                }

                _ = try await promptRunner.run(
                    template: template,
                    chunks: chunking.chunks,
                    provider: provider,
                    apiKey: apiKey,
                    enableStreaming: settingsStore.enableStreaming,
                    onUpdate: { partial in
                        await MainActor.run {
                            self.panelState.resultText = partial
                            self.panelController.refit()
                        }
                    }
                )

                await MainActor.run {
                    self.panelState.isLoading = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.panelState.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.panelState.isLoading = false
                    self.panelState.errorMessage = self.userFacingErrorMessage(for: error)
                }
            }
        }
    }

    func retryLastAction() {
        guard let action = panelState.lastAction, let input = panelState.lastInputText else { return }
        panelState.selectedText = input
        run(action: action)
    }

    func cancelCurrentRequest() {
        runningTask?.cancel()
    }

    func testProviderConnectivity(provider: LLMProvider, apiKey: String) async -> ProviderConnectivityReport {
        var report = ProviderConnectivityReport(
            baseURL: .unknown,
            apiKey: .unknown,
            model: .unknown,
            message: ""
        )

        let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedBaseURL.isEmpty || URL(string: trimmedBaseURL) == nil {
            report.baseURL = .unavailable
            report.message = "Base URL 不合法"
        } else {
            report.baseURL = .available
        }

        if trimmedAPIKey.isEmpty {
            report.apiKey = .unavailable
            report.message = report.message.isEmpty ? "API Key 为空" : report.message
        } else {
            report.apiKey = .available
        }

        if trimmedModel.isEmpty {
            report.model = .unavailable
            report.message = report.message.isEmpty ? "Model 为空" : report.message
        } else {
            report.model = .available
        }

        guard report.baseURL != .unavailable,
              report.apiKey != .unavailable,
              report.model != .unavailable else {
            return report
        }

        var probeProvider = provider
        probeProvider.baseURL = trimmedBaseURL
        probeProvider.model = trimmedModel

        do {
            _ = try await llmClient.complete(
                prompt: "Reply with exactly: OK",
                provider: probeProvider,
                apiKey: trimmedAPIKey
            )

            report.baseURL = .available
            report.apiKey = .available
            report.model = .available
            report.message = "连通成功"
            return report
        } catch let error as LLMError {
            let message = connectivityErrorMessage(for: error)
            report.message = message
            applyConnectivityErrorCode(error.errorCode, to: &report)
            inferConnectivityFailures(from: message, report: &report)
            return report
        } catch {
            let message = userFacingErrorMessage(for: error)
            report.message = message
            inferConnectivityFailures(from: message, report: &report)
            return report
        }
    }

    private func preflightForTranslation() -> TranslationPreflight? {
        guard let provider = settingsStore.selectedProvider else {
            panelState.errorMessage = "请先在设置里配置 Provider"
            return nil
        }

        let apiKey = settingsStore.apiKey(for: provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            panelState.errorMessage = "未设置 API Key（请在设置里填写）"
            return nil
        }

        let selectedText = sanitizeSelectedText(panelState.selectedText)
        guard !selectedText.isEmpty else {
            panelState.errorMessage = "未读取到选中文本"
            return nil
        }

        panelState.errorMessage = nil
        return TranslationPreflight(provider: provider, apiKey: apiKey, selectedText: selectedText)
    }

    private func updateSelectionMonitor(_ enabled: Bool) {
        if let selectionMonitor {
            NSEvent.removeMonitor(selectionMonitor)
            self.selectionMonitor = nil
        }
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }

        guard enabled else {
            pendingSelectionText = ""
            mouseDownLocation = nil
            selectionBubbleController.hide()
            return
        }

        // Track mouse-down position so we can distinguish clicks from drag-selections.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.mouseDownLocation = NSEvent.mouseLocation
        }

        selectionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.autoPopupOnSelectionIfNeeded()
            }
        }
    }

    private func autoPopupOnSelectionIfNeeded() async {
        // Avoid fighting the user when the panel is already visible.
        if panelController.isVisible {
            return
        }

        let now = Date()
        if now < suppressAutoPopupUntil {
            return
        }

        // If the mouse barely moved between down and up, it's a click — not a selection drag.
        // Skip to avoid showing the bubble on stale/previous selection text.
        let mouseUpLocation = NSEvent.mouseLocation
        if let downLocation = mouseDownLocation {
            let dx = mouseUpLocation.x - downLocation.x
            let dy = mouseUpLocation.y - downLocation.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < 4 {
                return
            }
        }
        mouseDownLocation = nil

        // Small delay to let the system update the selection state after mouse-up.
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        guard selectionService.status() == .trusted else { return }
        guard let text = try? selectionService.getSelectedText() else { return }

        let trimmed = sanitizeSelectedText(text)
        guard trimmed.count >= 2 else { return }

        if trimmed == lastAutoPopupText, now.timeIntervalSince(lastAutoPopupAt) < 0.6 {
            return
        }

        lastAutoPopupText = trimmed
        lastAutoPopupAt = now

        pendingSelectionText = trimmed

        let point = NSEvent.mouseLocation
        selectionBubbleController.show(at: point)
    }

    func accessibilityStatus() -> AccessibilitySelectionService.Status {
        selectionService.status()
    }

    func openAccessibilitySettings() {
        selectionService.openAccessibilitySettings()
    }

    private func updateHotKeyRegistration(_ shortcut: KeyboardShortcut?) {
        do {
            if let shortcut {
                try hotKeyManager.register(shortcut: shortcut)
            } else {
                hotKeyManager.unregister()
            }
        } catch {
            // Best-effort.
        }
    }

    private func handlePanelDidClose() {
        pendingSelectionText = ""
        mouseDownLocation = nil
        selectionBubbleController.hide()
        suppressAutoPopupUntil = Date().addingTimeInterval(0.9)
    }

    private func applyConnectivityErrorCode(_ code: TranslationErrorCode, to report: inout ProviderConnectivityReport) {
        switch code {
        case .unauthorized:
            report.apiKey = .unavailable
        case .rateLimited:
            report.model = report.model == .unknown ? .available : report.model
        case .timeout, .network:
            report.baseURL = .unavailable
        case .noPermission:
            report.apiKey = .unavailable
            report.model = .unavailable
        case .emptyResponse:
            report.model = .unavailable
        case .invalidResponse:
            report.model = .unavailable
        case .invalidBaseURL:
            report.baseURL = .unavailable
        case .unknown:
            break
        }
    }

    private func connectivityErrorMessage(for error: LLMError) -> String {
        if let reason = error.failureReason,
           !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(error.localizedDescription)\n\(reason)"
        }

        return error.localizedDescription
    }


    private func userFacingErrorMessage(for error: Error) -> String {
        if let llmError = error as? LLMError {
            return llmError.localizedDescription
        }

        let message = error.localizedDescription
        let lowercased = message.lowercased()

        if lowercased.contains("401") || lowercased.contains("unauthorized") || lowercased.contains("invalid key") {
            return "API Key 无效或已过期（401）"
        }
        if lowercased.contains("429") || lowercased.contains("rate limit") {
            return "请求过于频繁，请稍后重试（429）"
        }
        if lowercased.contains("timed out") || lowercased.contains("timeout") {
            return "网络超时，请检查网络后重试"
        }
        if lowercased.contains("403") || lowercased.contains("forbidden") || lowercased.contains("permission") {
            return "无权限访问该模型或接口（403）"
        }
        if lowercased.contains("empty") || lowercased.contains("no content") {
            return "模型未返回内容，请重试"
        }

        return message
    }

    private func sanitizeSelectedText(_ raw: String) -> String {
        let normalizedLineEndings = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let withoutZeroWidth = normalizedLineEndings.replacingOccurrences(
            of: #"[\u200B\u200C\u200D\uFEFF\u2060]"#,
            with: "",
            options: .regularExpression
        )

        let compressedBlankLines = withoutZeroWidth.replacingOccurrences(
            of: #"\n[ \t]*\n(?:[ \t]*\n)+"#,
            with: "\n\n",
            options: .regularExpression
        )

        return compressedBlankLines.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferConnectivityFailures(from message: String, report: inout ProviderConnectivityReport) {
        let lowercased = message.lowercased()

        if lowercased.contains("api key")
            || lowercased.contains("unauthorized")
            || lowercased.contains("invalid key")
            || lowercased.contains("401")
            || lowercased.contains("403") {
            report.apiKey = .unavailable
        }

        if lowercased.contains("model")
            || lowercased.contains("not found")
            || lowercased.contains("does not exist") {
            report.model = .unavailable
        }

        if lowercased.contains("base url")
            || lowercased.contains("invalid url")
            || lowercased.contains("host")
            || lowercased.contains("dns")
            || lowercased.contains("timed out")
            || lowercased.contains("cannot connect") {
            report.baseURL = .unavailable
        }
    }
}

enum ConnectivityCheckState: Equatable {
    case available
    case unavailable
    case unknown

    var label: String {
        switch self {
        case .available:
            "可用"
        case .unavailable:
            "不可用"
        case .unknown:
            "待确认"
        }
    }

    var systemImage: String {
        switch self {
        case .available:
            "checkmark.circle.fill"
        case .unavailable:
            "xmark.circle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }
}

struct ProviderConnectivityReport: Equatable {
    var baseURL: ConnectivityCheckState
    var apiKey: ConnectivityCheckState
    var model: ConnectivityCheckState
    var message: String
}

private struct TranslationPreflight {
    var provider: LLMProvider
    var apiKey: String
    var selectedText: String
}

struct PanelState: Equatable {
    var selectedText: String = ""
    var isLoading: Bool = false
    var resultText: String = ""
    var errorMessage: String?
    var noticeMessage: String?
    var lastAction: PanelAction?
    var lastInputText: String?
    var phase: PanelPhase = .choose
}

enum PanelPhase: String, Codable, Equatable {
    case choose
    case result
}

enum PanelAction: String, Codable, CaseIterable {
    case translate

    var displayName: String {
        "翻译"
    }
}

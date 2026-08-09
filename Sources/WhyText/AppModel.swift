import AppKit
import Combine
import Foundation
import WhyTextCore

@MainActor
final class AppModel: ObservableObject {
    @Published var panelState = PanelState()
    @Published var selectionDiagnosticsReport: String = ""
    @Published var selectionDiagnosticsTextPreview: String = ""
    @Published var selectionDiagnosticsUpdatedAt: Date?
    @Published var selectionDiagnosticsPending: Bool = false

    var settingsStore: SettingsStore

    private let selectionService: AccessibilitySelectionService
    private let selectionReader: SelectionReader
    private let panelController: FloatingPanelController
    private let selectionBubbleController: SelectionBubbleController
    private let hotKeyManager: HotKeyManager
    private let settingsWindowController: SettingsWindowController
    private let connectivityProbe: ProviderConnectivityProbe
    private let translationSession: TranslationSession
    private let selectionAutoPopup: SelectionAutoPopupCoordinator

    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore = SettingsStore(),
        selectionService: AccessibilitySelectionService = AccessibilitySelectionService(),
        selectionReader: SelectionReader? = nil,
        llmClient: LLMClient = LLMClient(),
        panelController: FloatingPanelController = FloatingPanelController(),
        selectionBubbleController: SelectionBubbleController = SelectionBubbleController()
    ) {
        let resolvedSelectionReader = selectionReader ?? SelectionReader(accessibility: selectionService)
        self.settingsStore = settingsStore
        self.selectionService = selectionService
        self.selectionReader = resolvedSelectionReader
        self.panelController = panelController
        self.selectionBubbleController = selectionBubbleController
        self.settingsWindowController = SettingsWindowController()
        self.connectivityProbe = ProviderConnectivityProbe(llmClient: llmClient)
        self.translationSession = TranslationSession(promptRunner: PromptRunner(llmClient: llmClient))
        self.selectionAutoPopup = SelectionAutoPopupCoordinator(
            selectionReader: resolvedSelectionReader,
            selectionBubbleController: selectionBubbleController
        )
        self.hotKeyManager = HotKeyManager()

        selectionAutoPopup.isPanelVisible = { [weak panelController] in
            panelController?.isVisible ?? false
        }

        settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settingsStore.$autoPopupOnSelection
            .sink { [weak self] enabled in
                self?.selectionAutoPopup.setEnabled(enabled)
            }
            .store(in: &cancellables)

        selectionAutoPopup.setEnabled(settingsStore.autoPopupOnSelection)

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

        selectionBubbleController.onTranslate = { [weak self] in
            Task { @MainActor in
                self?.openPanelFromSelectionBubble(action: .translate)
            }
        }

        selectionBubbleController.onExplain = { [weak self] in
            Task { @MainActor in
                self?.openPanelFromSelectionBubble(action: .explain)
            }
        }

        panelController.onDidClose = { [weak self] in
            Task { @MainActor in
                self?.selectionAutoPopup.handlePanelDidClose()
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

    private func openPanelFromSelectionBubble(action: PanelAction) {
        let selectedText = AccessibilitySelectionHelpers.sanitizeSelectedText(selectionAutoPopup.pendingText)
        guard !selectedText.isEmpty else { return }

        presentPanel(selectedText: selectedText)
        run(action: action)
    }

    private func openPanelFlow() async {
        var selectedText: String = ""
        var selectionError: String?

        do {
            let selection = try await selectionReader.readSelectedText()
            selectedText = AccessibilitySelectionHelpers.sanitizeSelectedText(selection.text)
        } catch {
            selectionError = TranslationErrorPresenter.userFacingMessage(for: error)
        }

        let trimmed = AccessibilitySelectionHelpers.sanitizeSelectedText(selectedText)
        presentPanel(
            selectedText: trimmed,
            errorMessage: selectionError ?? (trimmed.isEmpty ? "未读取到选中文本。请先选中一段文字，并确认已授权辅助功能。" : nil)
        )

        guard selectionError == nil, !trimmed.isEmpty else {
            return
        }

        run(action: .translate)
    }

    private func presentPanel(selectedText: String = "", errorMessage: String? = nil) {
        selectionAutoPopup.hideBubble()
        translationSession.cancel()

        panelState = PanelState()
        panelState.phase = .choose
        panelState.selectedText = selectedText
        panelState.errorMessage = errorMessage
        panelState.noticeMessage = nil
        panelState.isLoading = false

        let point = NSEvent.mouseLocation
        panelController.show(at: point) {
            FloatingPanelTitlebarView()
                .environmentObject(self)
        } content: {
            FloatingPanelView()
                .environmentObject(self)
        }
    }

    func closePanel() {
        translationSession.cancel()
        panelController.close()
    }

    func copyResultRichTextToPasteboard() {
        guard !panelState.resultText.isEmpty else { return }

        let fontSize = CGFloat(settingsStore.translationFontSize)
        let attributed = MarkdownRenderer.pasteboardAttributedString(
            panelState.resultText,
            fontSize: fontSize
        )
        let range = NSRange(location: 0, length: attributed.length)

        // RTF + plain only: AppKit HTML pasteboard encoding is unreliable across apps.
        let item = NSPasteboardItem()
        item.setString(attributed.string, forType: .string)

        if let rtf = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            item.setData(rtf, forType: .rtf)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    func run(action: PanelAction) {
        guard let preflight = preflightForTranslation() else {
            return
        }

        panelState.lastAction = action
        panelState.lastInputText = preflight.selectedText
        panelState.phase = .result
        panelState.errorMessage = nil
        panelState.noticeMessage = nil
        panelState.isLoading = true
        panelState.resultText = ""

        let template: String
        switch action {
        case .translate:
            template = settingsStore.translatePromptTemplate
        case .explain:
            template = settingsStore.explainPromptTemplate
        }

        translationSession.run(
            mode: action.translationMode,
            template: template,
            selectedText: preflight.selectedText,
            provider: preflight.provider,
            apiKey: preflight.apiKey,
            maxInputCharacters: settingsStore.maxInputCharacters,
            splitLongInput: settingsStore.splitLongInput,
            enableStreaming: settingsStore.enableStreaming,
            onNotice: { [weak self] notice in
                self?.panelState.noticeMessage = notice
            },
            onPartialResult: { [weak self] partial in
                self?.panelState.resultText = partial
                self?.panelController.refit()
            },
            onFinished: { [weak self] result in
                guard let self else { return }
                self.panelState.isLoading = false
                if case .failure(let error) = result {
                    self.panelState.errorMessage = TranslationErrorPresenter.userFacingMessage(for: error)
                }
            }
        )
    }

    func retryLastAction() {
        guard let action = panelState.lastAction, let input = panelState.lastInputText else { return }
        panelState.selectedText = input
        run(action: action)
    }

    func cancelCurrentRequest() {
        translationSession.cancel()
    }

    func testProviderConnectivity(provider: LLMProvider, apiKey: String) async -> ProviderConnectivityReport {
        await connectivityProbe.test(provider: provider, apiKey: apiKey)
    }

    private func preflightForTranslation() -> TranslationPreflight? {
        guard let provider = settingsStore.selectedProvider else {
            panelState.errorMessage = "请先在设置中添加服务商"
            return nil
        }

        let apiKey = settingsStore.apiKey(for: provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            panelState.errorMessage = "请先在设置中填写 API Key"
            return nil
        }

        let selectedText = AccessibilitySelectionHelpers.sanitizeSelectedText(panelState.selectedText)
        guard !selectedText.isEmpty else {
            panelState.errorMessage = "未读取到选中文本。请先选中一段文字，并确认已授权辅助功能。"
            return nil
        }

        panelState.errorMessage = nil
        return TranslationPreflight(provider: provider, apiKey: apiKey, selectedText: selectedText)
    }

    func accessibilityStatus() -> AccessibilitySelectionService.Status {
        selectionService.status()
    }

    func runSelectionDiagnostics() {
        let diagnostics = selectionService.collectDiagnostics()
        selectionDiagnosticsReport = diagnostics.report
        selectionDiagnosticsTextPreview = diagnostics.selectedText ?? ""
        selectionDiagnosticsUpdatedAt = Date()
        selectionDiagnosticsPending = false
    }

    func runSelectionDiagnosticsWithDelay(seconds: Double = 2.0) {
        selectionDiagnosticsPending = true
        selectionDiagnosticsReport = "等待 \(String(format: "%.1f", seconds)) 秒后采样，请切回目标应用并选中文本..."
        selectionDiagnosticsTextPreview = ""

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.runSelectionDiagnostics()
        }
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
}

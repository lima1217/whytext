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
    /// Pinned panels ignore clicks outside them; persists across panel openings.
    @Published var isPanelPinned: Bool = false
    /// Why a shortcut isn't active, if it isn't. Kept as state, not text, so the
    /// message follows the interface language.
    @Published private(set) var hotKeyIssue: HotKeyIssue?
    @Published private(set) var ocrHotKeyIssue: HotKeyIssue?

    var settingsStore: SettingsStore
    let historyStore: HistoryStore
    let updateChecker = UpdateChecker()

    private let selectionService: AccessibilitySelectionService
    private let selectionReader: SelectionReader
    private let panelController: FloatingPanelController
    private let selectionBubbleController: SelectionBubbleController
    private let hotKeyManager: HotKeyManager
    private let ocrHotKeyManager = HotKeyManager(id: 2)
    private let screenTextRecognizer = ScreenTextRecognizer()
    private var isCapturingScreenText = false
    private let settingsWindowController: SettingsWindowController
    private let connectivityProbe: ProviderConnectivityProbe
    private let translationSession: TranslationSession
    private let selectionAutoPopup: SelectionAutoPopupCoordinator

    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore = SettingsStore(),
        historyStore: HistoryStore = HistoryStore(),
        selectionService: AccessibilitySelectionService = AccessibilitySelectionService(),
        selectionReader: SelectionReader? = nil,
        llmClient: LLMClient = LLMClient(),
        panelController: FloatingPanelController = FloatingPanelController(),
        selectionBubbleController: SelectionBubbleController = SelectionBubbleController()
    ) {
        let resolvedSelectionReader = selectionReader ?? SelectionReader(accessibility: selectionService)
        self.settingsStore = settingsStore
        self.historyStore = historyStore
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

        BubbleDebugLog.log(
            "startup axTrusted=\(selectionService.status() == .trusted) autoPopupSetting=\(settingsStore.autoPopupOnSelection) version=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") path=\(Bundle.main.bundlePath)"
        )

        settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        historyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        updateChecker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settingsStore.$autoCheckForUpdates
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updateChecker.setAutomaticChecks(enabled: enabled)
            }
            .store(in: &cancellables)

        settingsStore.$saveHistory
            .sink { [weak historyStore] enabled in
                if !enabled { historyStore?.clear() }
            }
            .store(in: &cancellables)

        // `@Published` sinks emit the current value on subscribe — that installs monitors once.
        settingsStore.$autoPopupOnSelection
            .sink { [weak self] enabled in
                self?.selectionAutoPopup.setEnabled(enabled)
            }
            .store(in: &cancellables)

        settingsStore.$interfaceLanguage
            .sink { [weak self] language in
                L10n.language = language
                self?.settingsWindowController.refreshTitle()
            }
            .store(in: &cancellables)

        // Both at once: the screenshot shortcut must not reuse the main one.
        settingsStore.$hotKeyShortcut
            .combineLatest(settingsStore.$ocrHotKeyShortcut)
            .sink { [weak self] main, ocr in
                self?.registerHotKeys(main: main, ocr: ocr)
            }
            .store(in: &cancellables)
        hotKeyManager.onPressed = { [weak self] in
            Task { @MainActor in
                self?.openPanelFromHotKey()
            }
        }

        ocrHotKeyManager.onPressed = { [weak self] in
            Task { @MainActor in
                self?.startScreenTextCapture()
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

        panelController.shouldCloseOnOutsideClick = { [weak self] in
            self?.isPanelPinned == false
        }

        panelController.onOutsideClick = { [weak self] in
            Task { @MainActor in
                self?.closePanel()
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
        // System shortcuts may have changed since launch.
        registerHotKeys(main: settingsStore.hotKeyShortcut, ocr: settingsStore.ocrHotKeyShortcut)
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
        let selectedText: String
        do {
            let selection = try await selectionReader.readSelectedText()
            selectedText = AccessibilitySelectionHelpers.sanitizeSelectedText(selection.text)
        } catch SelectionError.notTrusted {
            openManualInput(
                hint: L10n.t("未授权辅助功能，读不到选中文本。可以直接输入或粘贴："),
                needsAccessibility: true
            )
            return
        } catch {
            selectedText = ""
        }

        guard !selectedText.isEmpty else {
            openManualInput()
            return
        }

        presentPanel(selectedText: selectedText)
        run(action: .translate)
    }

    /// Opens the panel with a text box; used when nothing is selected.
    func openManualInput(hint: String? = nil, needsAccessibility: Bool = false) {
        presentPanel()
        panelState.phase = .input
        panelState.inputHint = hint
        panelState.inputNeedsAccessibility = needsAccessibility
    }

    func submitManualInput(_ text: String, action: PanelAction) {
        let input = AccessibilitySelectionHelpers.sanitizeSelectedText(text)
        guard !input.isEmpty else { return }
        panelState.selectedText = input
        panelState.inputHint = nil
        panelState.phase = .result
        run(action: action)
        DispatchQueue.main.async { [weak self] in self?.refitPanel() }
    }

    /// Drag out a screen region, read its text on-device, and translate it.
    func startScreenTextCapture() {
        guard !isCapturingScreenText else { return }
        isCapturingScreenText = true

        // Keep our own windows out of the shot.
        closePanel()
        selectionAutoPopup.hideBubble()

        Task { @MainActor in
            defer { isCapturingScreenText = false }
            do {
                let preferred = [settingsStore.primaryLanguage, settingsStore.secondaryLanguage]
                guard let text = try await screenTextRecognizer.captureAndRecognize(preferred: preferred) else {
                    return // cancelled
                }
                presentPanel(selectedText: text)
                run(action: .translate)
            } catch {
                presentPanel(errorMessage: error.localizedDescription)
                if case ScreenTextRecognizer.RecognitionError.permissionDenied = error {
                    panelState.errorSystemSettingsURL = ScreenTextRecognizer.screenRecordingSettingsURL
                }
            }
        }
    }

    func openErrorSystemSettings() {
        guard let url = panelState.errorSystemSettingsURL else { return }
        NSWorkspace.shared.open(url)
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

    func togglePanelPinned() {
        isPanelPinned.toggle()
    }

    /// Re-measure the panel after content changes size outside of streaming.
    func refitPanel() {
        panelController.refit(force: true)
    }

    /// The result plus any follow-up exchanges, as Markdown.
    private var transcriptMarkdown: String {
        var parts = [panelState.resultText.trimmingCharacters(in: .whitespacesAndNewlines)]
        for turn in panelState.followUps where !turn.answer.isEmpty {
            parts.append("**" + L10n.f("问：%@", turn.question) + "**")
            parts.append(turn.answer.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parts.joined(separator: "\n\n")
    }

    func copyResultRichTextToPasteboard() {
        guard !panelState.resultText.isEmpty else { return }

        let fontSize = CGFloat(settingsStore.translationFontSize)
        let attributed = MarkdownRenderer.pasteboardAttributedString(
            transcriptMarkdown,
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

    /// `target` overrides the automatic direction for translations. Identical earlier
    /// requests are served from history unless `bypassHistory` is set.
    func run(action: PanelAction, target: TranslationLanguage? = nil, bypassHistory: Bool = false) {
        guard let preflight = preflightForTranslation() else {
            return
        }

        let targetLanguage: TranslationLanguage
        switch action {
        case .translate:
            targetLanguage = target ?? TranslationDirection.target(
                for: preflight.selectedText,
                primary: settingsStore.primaryLanguage,
                secondary: settingsStore.secondaryLanguage
            )
        case .explain:
            // Explanations are for the reader, so a {{target}} in the explain prompt
            // always means their primary language.
            targetLanguage = settingsStore.primaryLanguage
        }

        panelState.targetLanguage = action == .translate ? targetLanguage : nil
        panelState.conversation = []
        panelState.followUps = []
        panelState.isFromHistory = false
        panelState.lastAction = action
        panelState.lastInputText = preflight.selectedText
        panelState.phase = .result
        panelState.errorMessage = nil
        panelState.noticeMessage = nil
        panelState.isLoading = true
        panelState.activity = nil
        panelState.resultText = ""

        let template: String
        switch action {
        case .translate:
            template = settingsStore.translatePromptTemplate
        case .explain:
            template = settingsStore.explainPromptTemplate
        }

        let historyKey = HistoryCacheKey(
            action: action,
            targetLanguage: targetLanguage,
            providerID: preflight.provider.id,
            baseURL: preflight.provider.baseURL,
            model: preflight.provider.model,
            apiMode: preflight.provider.apiMode,
            template: template,
            maxInputCharacters: settingsStore.maxInputCharacters,
            splitLongInput: settingsStore.splitLongInput
        )

        if settingsStore.saveHistory, !bypassHistory,
           let entry = historyStore.lookup(key: historyKey, sourceText: preflight.selectedText) {
            translationSession.cancel()
            apply(entry)
            var refreshed = entry
            refreshed.date = Date()
            historyStore.record(refreshed)
            return
        }

        // The first partial of a run may need to shrink a panel left tall by the
        // previous result; after that, growth-only refits are enough.
        var didRefitThisRun = false

        translationSession.run(
            mode: action.translationMode,
            template: template,
            selectedText: preflight.selectedText,
            targetLanguage: targetLanguage,
            provider: preflight.provider,
            apiKey: preflight.apiKey,
            maxInputCharacters: settingsStore.maxInputCharacters,
            splitLongInput: settingsStore.splitLongInput,
            enableStreaming: settingsStore.enableStreaming,
            onNotice: { [weak self] notice in
                self?.panelState.noticeMessage = notice
            },
            onActivity: { [weak self] activity in
                self?.panelState.activity = activity
            },
            onPartialResult: { [weak self] partial in
                self?.panelState.activity = nil
                self?.panelState.resultText = partial
                self?.panelController.refit(force: !didRefitThisRun)
                didRefitThisRun = true
            },
            onFinished: { [weak self] result in
                guard let self else { return }
                self.panelState.isLoading = false
                self.panelState.activity = nil
                switch result {
                case .success(let conversation):
                    self.panelState.conversation = conversation
                    // Empty means cancelled; a partial answer isn't worth reusing.
                    if self.settingsStore.saveHistory, !conversation.isEmpty {
                        self.historyStore.record(HistoryEntry(
                            date: Date(),
                            key: historyKey,
                            sourceText: preflight.selectedText,
                            resultText: self.panelState.resultText,
                            conversation: conversation
                        ))
                    }
                case .failure(let error):
                    self.panelState.errorMessage = TranslationErrorPresenter.userFacingMessage(for: error)
                    self.panelState.errorNeedsSettings = TranslationErrorPresenter.needsSettings(for: error)
                }
            }
        )
    }

    func retryLastAction() {
        guard let action = panelState.lastAction, let input = panelState.lastInputText else { return }
        panelState.selectedText = input
        run(action: action, target: panelState.targetLanguage)
    }

    /// Request a fresh answer for a result restored from history.
    func regenerate() {
        guard let action = panelState.lastAction else { return }
        run(action: action, target: panelState.targetLanguage, bypassHistory: true)
    }

    func showHistoryEntry(_ entry: HistoryEntry) {
        presentPanel(selectedText: entry.sourceText)
        apply(entry)
    }

    func clearHistory() {
        historyStore.clear()
    }

    private func apply(_ entry: HistoryEntry) {
        panelState.lastAction = entry.key.action
        panelState.lastInputText = entry.sourceText
        panelState.targetLanguage = entry.key.action == .translate ? entry.key.targetLanguage : nil
        panelState.phase = .result
        panelState.errorMessage = nil
        panelState.noticeMessage = nil
        panelState.isLoading = false
        panelState.activity = nil
        panelState.resultText = entry.resultText
        panelState.conversation = entry.conversation
        panelState.followUps = []
        panelState.isFromHistory = true
        panelController.refit(force: true)
    }

    /// Switch between translate and explain on the same selection.
    func switchAction(to action: PanelAction) {
        guard action != panelState.lastAction || panelState.errorMessage != nil else { return }
        run(action: action)
    }

    func retranslate(to target: TranslationLanguage) {
        guard target != panelState.targetLanguage else { return }
        run(action: .translate, target: target)
    }

    func askFollowUp(_ rawQuestion: String) {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, panelState.canAskFollowUp,
              let action = panelState.lastAction else { return }

        guard let provider = settingsStore.selectedProvider else { return }
        let apiKey = settingsStore.apiKey(for: provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        let history = panelState.conversation
        let turn = FollowUpTurn(question: question)
        let turnID = turn.id
        panelState.followUps.append(turn)
        panelState.isLoading = true
        panelState.activity = nil
        refitPanel()

        func update(_ body: (inout FollowUpTurn) -> Void) {
            guard let index = panelState.followUps.firstIndex(where: { $0.id == turnID }) else { return }
            body(&panelState.followUps[index])
        }

        translationSession.runFollowUp(
            question: question,
            history: history,
            mode: action.translationMode,
            provider: provider,
            apiKey: apiKey,
            enableStreaming: settingsStore.enableStreaming,
            onActivity: { [weak self] activity in
                self?.panelState.activity = activity
            },
            onPartialResult: { [weak self] partial in
                guard let self else { return }
                self.panelState.activity = nil
                update { $0.answer = partial }
                self.panelController.refit()
            },
            onFinished: { [weak self] result in
                guard let self else { return }
                self.panelState.isLoading = false
                self.panelState.activity = nil
                switch result {
                case .success(let answer):
                    // A cancelled question leaves no answer and stays out of the context.
                    guard !answer.isEmpty else { return }
                    update { $0.answer = answer }
                    self.panelState.conversation = history + [
                        ConversationMessage(role: .user, content: question),
                        ConversationMessage(role: .assistant, content: answer),
                    ]
                case .failure(let error):
                    update { $0.errorMessage = TranslationErrorPresenter.userFacingMessage(for: error) }
                }
                self.panelController.refit()
            }
        )
    }

    func retryFollowUp(id: FollowUpTurn.ID) {
        guard let index = panelState.followUps.firstIndex(where: { $0.id == id }) else { return }
        let question = panelState.followUps.remove(at: index).question
        askFollowUp(question)
    }

    func cancelCurrentRequest() {
        translationSession.cancel()
    }

    func testProviderConnectivity(provider: LLMProvider, apiKey: String) async -> ProviderConnectivityReport {
        await connectivityProbe.test(provider: provider, apiKey: apiKey)
    }

    private func preflightForTranslation() -> TranslationPreflight? {
        guard let provider = settingsStore.selectedProvider else {
            panelState.errorMessage = L10n.t("请先在设置中添加服务商")
            panelState.errorNeedsSettings = true
            return nil
        }

        let apiKey = settingsStore.apiKey(for: provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            panelState.errorMessage = L10n.t("请先在设置中填写 API Key")
            panelState.errorNeedsSettings = true
            return nil
        }

        let selectedText = AccessibilitySelectionHelpers.sanitizeSelectedText(panelState.selectedText)
        guard !selectedText.isEmpty else {
            panelState.errorMessage = L10n.t("未读取到选中文本。请先选中一段文字，并确认已授权辅助功能。")
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
        selectionDiagnosticsReport = L10n.f("等待 %@ 秒后采样，请切回目标应用并选中文本…", String(format: "%.1f", seconds))
        selectionDiagnosticsTextPreview = ""

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.runSelectionDiagnostics()
        }
    }

    func openAccessibilitySettings() {
        selectionService.openAccessibilitySettings()
    }

    private func registerHotKeys(main: KeyboardShortcut?, ocr: KeyboardShortcut?) {
        hotKeyIssue = Self.register(main, with: hotKeyManager)

        if let ocr, ocr == main {
            ocrHotKeyManager.unregister()
            ocrHotKeyIssue = .sameAsTranslateShortcut
        } else {
            ocrHotKeyIssue = Self.register(ocr, with: ocrHotKeyManager)
        }
    }

    /// Registration itself rarely fails; the useful check is against enabled macOS
    /// shortcuts. Other apps' shortcuts can't be detected, so Settings mentions it.
    private static func register(_ shortcut: KeyboardShortcut?, with manager: HotKeyManager) -> HotKeyIssue? {
        guard let shortcut else {
            manager.unregister()
            return nil
        }
        do {
            try manager.register(shortcut: shortcut)
        } catch {
            manager.unregister()
            return .registrationFailed(shortcut)
        }
        return HotKeyManager.conflictsWithSystemShortcut(shortcut) ? .conflictsWithSystemShortcut(shortcut) : nil
    }
}

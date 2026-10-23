import AppKit
import SwiftUI
import WhyTextCore

private enum PanelTokens {
    static let horizontalPadding: CGFloat = Spacing.x4   // 16
    static let bottomPadding: CGFloat = Spacing.x4       // 16
    static let bodyFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let iconSize: CGFloat = 13
    /// Reading column: ~30–35 CJK / ~55–65 Latin glyphs at default 16pt body.
    static let minWidth: CGFloat = 360
    static let idealWidth: CGFloat = 520
    static let minContentHeight: CGFloat = 72
    static let maxHeight: CGFloat = 420
    static let sourceMaxHeight: CGFloat = 120
    /// Matches the grouped-form sections in Settings.
    static let cardRadius: CGFloat = 10
    static let cardPadding: CGFloat = Spacing.x3
    static let cardFill = Color.dynamic(light: "#FFFFFFA6", dark: "#FFFFFF0F")
}

private extension View {
    /// Content card in the style of a Settings form section.
    func panelCard(padding: CGFloat = PanelTokens.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PanelTokens.cardRadius, style: .continuous)
                    .fill(PanelTokens.cardFill)
            )
            .hairlineBorder(cornerRadius: PanelTokens.cardRadius)
    }
}

struct FloatingPanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()

            // Material weight: soft fill keeps vibrancy text legible without stacking glass on glass.
            // Reduce Transparency → frostier/solid surface.
            Group {
                if MotionPreference.reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    Color(nsColor: .windowBackgroundColor).opacity(0.18)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.x2) {
                    if !appModel.panelState.selectedText.isEmpty {
                        SourceTextDisclosure(text: appModel.panelState.selectedText)
                    }

                    Group {
                        content
                    }
                    .animation(AstryxMotion.smooth, value: contentStateKey)

                    if showsHistoryNote {
                        HistoryNoteRow()
                            .transition(.opacity)
                    }

                    if showsFollowUpField {
                        FollowUpInputBar()
                            .transition(.opacity)
                    }
                }
                .animation(AstryxMotion.smooth, value: showsFollowUpField)
                .padding(.top, Spacing.x3)
                .padding(.horizontal, PanelTokens.horizontalPadding)
                .padding(.bottom, PanelTokens.bottomPadding)

                if let noticeText, !noticeText.isEmpty {
                    Label {
                        Text(noticeText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.system(size: PanelTokens.metaFontSize))
                    .foregroundStyle(AstryxColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PanelTokens.horizontalPadding + Spacing.x1)
                    .padding(.top, -Spacing.x2)
                        .padding(.bottom, PanelTokens.bottomPadding)
                        .accessibilityAddTraits(.updatesFrequently)
                        .transition(
                            MotionPreference.reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 8)),
                                    removal: .opacity.combined(with: .offset(y: -12))
                                )
                        )
                }
            }
            .animation(AstryxMotion.smooth, value: noticeText)
        }
        .offset(x: shakeOffset)
        .onExitCommand { appModel.closePanel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            errorView(error)
                .transition(panelContentTransition)
        } else if appModel.panelState.phase == .input {
            ManualInputView()
                .transition(panelContentTransition)
        } else if appModel.panelState.isLoading && !hasResult {
            loadingView
                .transition(panelContentTransition)
        } else {
            resultView
                .transition(panelContentTransition)
        }
    }

    private var panelContentTransition: AnyTransition {
        if MotionPreference.reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: -12))
        )
    }

    private var resultView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.x3) {
                    MarkdownTextView(markdown: displayText, fontSize: fontSize)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(appModel.panelState.followUps) { turn in
                        FollowUpTurnView(turn: turn, fontSize: fontSize)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.scrollBottomID)
                }
                .padding(PanelTokens.cardPadding)
            }
            .background(
                RoundedRectangle(cornerRadius: PanelTokens.cardRadius, style: .continuous)
                    .fill(PanelTokens.cardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: PanelTokens.cardRadius, style: .continuous))
            .hairlineBorder(cornerRadius: PanelTokens.cardRadius)
            .onChange(of: appModel.panelState.followUps) { _ in
                proxy.scrollTo(Self.scrollBottomID, anchor: .bottom)
            }
        }
        .frame(minWidth: PanelTokens.minWidth, idealWidth: PanelTokens.idealWidth, maxHeight: PanelTokens.maxHeight)
    }

    private static let scrollBottomID = "result-bottom"

    private var fontSize: CGFloat {
        CGFloat(appModel.settingsStore.translationFontSize)
    }

    private var showsHistoryNote: Bool {
        appModel.panelState.isFromHistory && !appModel.panelState.isLoading && hasResult
    }

    private var showsFollowUpField: Bool {
        hasResult
            && appModel.panelState.lastAction != nil
            && (appModel.panelState.errorMessage?.isEmpty ?? true)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: Spacing.x2_5) {
            skeletonBar(widthRatio: 1.0)
            skeletonBar(widthRatio: 0.82)
            skeletonBar(widthRatio: 0.6)
        }
        .frame(
            minWidth: PanelTokens.minWidth - PanelTokens.cardPadding * 2,
            idealWidth: PanelTokens.idealWidth,
            minHeight: PanelTokens.minContentHeight - PanelTokens.cardPadding * 2,
            alignment: .top
        )
        .panelCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func skeletonBar(widthRatio: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
            .fill(AstryxColor.overlayHover)
            .frame(height: 8)
            .frame(maxWidth: .infinity)
            .overlay(
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                        .fill(AstryxColor.borderEmphasized.opacity(0.5))
                        .frame(width: geo.size.width * 0.35, height: 8)
                        .modifier(SkeletonShimmerModifier(width: geo.size.width))
                }
            )
            .mask(
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                        .frame(width: geo.size.width * widthRatio, height: 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
    }

    /// Error: a card with the message and recovery actions. Shake animation on appear.
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.x2) {
                Image(systemName: Tone.danger.icon)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .accessibilityHidden(true)
                Text(message)
                    .foregroundStyle(AstryxColor.textPrimary)
                    .font(.system(size: PanelTokens.bodyFontSize))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.x2) {
                Spacer(minLength: 0)

                if appModel.panelState.errorSystemSettingsURL != nil {
                    Button(L10n.t("打开系统设置")) { appModel.openErrorSystemSettings() }
                }

                if appModel.panelState.errorNeedsSettings {
                    Button(L10n.t("打开设置")) { appModel.openSettingsWindow() }
                }

                if canRetry {
                    PanelIconButton(systemName: "arrow.clockwise", label: L10n.t("重试")) {
                        appModel.retryLastAction()
                    }
                }
            }
            .controlSize(.small)
        }
        .panelCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("出错了"))
        .accessibilityValue(message)
        .onAppear {
            guard !MotionPreference.reduceMotion else { return }
            triggerShake()
        }
    }

    // MARK: - Shake Animation

    private func triggerShake() {
        withAnimation(AstryxMotion.quick) { shakeOffset = 6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(AstryxMotion.quick) { shakeOffset = -5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(AstryxMotion.quick) { shakeOffset = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(AstryxMotion.quick) { shakeOffset = -2 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            // Momentum settle — underdamped only because the shake carried velocity.
            withAnimation(.astryxSpring(response: 0.18, damping: 0.82)) { shakeOffset = 0 }
        }
    }

    // MARK: - Helpers

    private var contentStateKey: String {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return "error"
        }
        if appModel.panelState.phase == .input {
            return "input"
        }
        if appModel.panelState.isLoading && !hasResult {
            return "loading"
        }
        return "result:\(hasResult)"
    }

    private var hasResult: Bool {
        !appModel.panelState.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var noticeText: String? {
        guard let notice = appModel.panelState.noticeMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !notice.isEmpty,
            !appModel.panelState.isLoading else {
            return nil
        }
        return notice
    }

    private var displayText: String {
        let trimmed = appModel.panelState.resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? " " : trimmed
    }

    private var accessibilityLabel: String {
        let action = appModel.panelState.lastAction ?? .translate
        if appModel.panelState.isLoading {
            return action.inProgressAccessibilityLabel
        }
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return action.failedTitle
        }
        if hasResult {
            return action.resultTitle
        }
        return action.windowTitle
    }

    private var accessibilityValue: String {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return error
        }
        if let noticeText, !noticeText.isEmpty {
            return noticeText
        }
        if hasResult {
            let trimmed = appModel.panelState.resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 120 {
                return String(trimmed.prefix(120)) + "…"
            }
            return trimmed
        }
        return ""
    }

    private var canRetry: Bool {
        appModel.panelState.lastAction != nil && appModel.panelState.lastInputText != nil
    }
}

struct FloatingPanelTitlebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: Spacing.x2) {
            if appModel.panelState.lastAction != nil {
                PanelModeSwitch()
            }

            if let target = appModel.panelState.targetLanguage, appModel.panelState.lastAction == .translate {
                TargetLanguageMenu(current: target)
            }

            if shouldShowStatus {
                HStack(spacing: Spacing.x1) {
                    statusIcon

                    if let activityTitle {
                        Text(activityTitle)
                            .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                            .foregroundStyle(statusTone.color)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, Spacing.x1_5)
                .padding(.trailing, activityTitle == nil ? Spacing.x1_5 : Spacing.x2)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(statusTone.mutedFill))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(headerTitle)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }

            Spacer(minLength: Spacing.x2)

            Button(action: { appModel.togglePanelPinned() }) {
                Image(systemName: appModel.isPanelPinned ? "pin.fill" : "pin")
                    .font(.system(size: PanelTokens.iconSize, weight: .medium))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(appModel.isPanelPinned ? Color.accentColor : AstryxColor.textSecondary)
                    .panelIconButton()
            }
            .buttonStyle(.quietIcon)
            .help(appModel.isPanelPinned ? L10n.t("取消固定：点击窗口外会关闭") : L10n.t("固定：点击窗口外不关闭"))
            .accessibilityLabel(appModel.isPanelPinned ? L10n.t("取消固定窗口") : L10n.t("固定窗口"))

            Button(action: copyResultIfPossible) {
                ContextualIconSwap(
                    isActive: didCopy,
                    activeSystemName: "checkmark",
                    inactiveSystemName: "doc.on.doc",
                    // doc.on.doc draws taller than pin at the same point size.
                    size: PanelTokens.iconSize - 1
                )
                .foregroundStyle(didCopy ? Tone.success.color : AstryxColor.textSecondary)
                .panelIconButton()
            }
            .buttonStyle(.quietIcon)
            .accessibilityLabel(didCopy ? L10n.t("已复制") : L10n.t("复制结果"))
            .disabled(appModel.panelState.isLoading || !hasResult)
            .opacity(hasResult ? 1 : 0)
            .allowsHitTesting(hasResult)
            .accessibilityHidden(!hasResult)
            .help(didCopy ? L10n.t("已复制") : L10n.t("复制"))
        }
        .frame(height: 32)
        .padding(.trailing, PanelTokens.horizontalPadding)
        .animation(AstryxMotion.smooth, value: shouldShowStatus)
        .accessibilityElement(children: .contain)
        .onDisappear { copyResetTask?.cancel() }
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            if let error = appModel.panelState.errorMessage, !error.isEmpty {
                Image(systemName: Tone.danger.icon)
                    .foregroundStyle(Tone.danger.color)
                    .font(.system(size: 12))
                    .transition(statusIconTransition)
            } else if appModel.panelState.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
                    .transition(statusIconTransition)
            } else if hasResult {
                Image(systemName: Tone.success.icon)
                    .foregroundStyle(Tone.success.color)
                    .font(.system(size: 12))
                    .transition(statusIconTransition)
            }
        }
        .frame(width: 12, height: 12)
        .animation(AstryxMotion.icon, value: contentStatusKey)
        .accessibilityHidden(true)
    }

    private var statusIconTransition: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.25))
    }

    private var contentStatusKey: String {
        if let error = appModel.panelState.errorMessage, !error.isEmpty { return "error" }
        if appModel.panelState.isLoading { return "loading" }
        if hasResult { return "result" }
        return "idle"
    }

    private func copyResultIfPossible() {
        guard !appModel.panelState.isLoading, hasResult else { return }
        appModel.copyResultRichTextToPasteboard()
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    private var hasResult: Bool {
        !appModel.panelState.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowStatus: Bool {
        appModel.panelState.isLoading || (appModel.panelState.errorMessage?.isEmpty == false)
    }

    private var statusTone: Tone {
        (appModel.panelState.errorMessage?.isEmpty == false) ? .danger : .neutral
    }

    /// The mode switch already names the action, so the badge only spells out
    /// thinking/searching and failures.
    private var activityTitle: String? {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return (appModel.panelState.lastAction ?? .translate).failedTitle
        }
        guard appModel.panelState.isLoading else { return nil }
        switch appModel.panelState.activity {
        case .thinking: return L10n.t("思考中")
        case .searching: return L10n.t("搜索中")
        case nil: return nil
        }
    }

    private var headerTitle: String {
        let action = appModel.panelState.lastAction ?? .translate
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return action.failedTitle
        }
        if appModel.panelState.isLoading {
            switch appModel.panelState.activity {
            case .thinking: return L10n.t("思考中")
            case .searching: return L10n.t("搜索中")
            case nil: return action.inProgressTitle
            }
        }
        return action.displayName
    }
}

private extension View {
    /// Shared frame and hover chrome for the panel's icon buttons.
    func panelIconButton() -> some View {
        frame(width: 28, height: 28)
            .quietButtonHover()
            .contentShape(Rectangle())
    }
}

/// Icon-only panel action, styled like the titlebar's pin and copy buttons.
private struct PanelIconButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: PanelTokens.iconSize, weight: .medium))
                .foregroundStyle(AstryxColor.textSecondary)
                .panelIconButton()
        }
        .buttonStyle(.quietIcon)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Skeleton shimmer

/// Sweeps a faint highlight across a skeleton bar to suggest in-progress content.
/// Skipped when Reduce Motion is on — looping oscillation near ~1Hz is vestibular noise.
private struct SkeletonShimmerModifier: ViewModifier, Animatable {
    let width: CGFloat
    @State private var offset: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .offset(x: MotionPreference.reduceMotion ? 0 : offset * width)
            .onAppear {
                guard !MotionPreference.reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 1.1)
                    .repeatForever(autoreverses: false)
                ) {
                    offset = 1.6
                }
            }
    }
}

// MARK: - Mode switch

/// Translate / explain toggle; switching reruns the same selection.
private struct PanelModeSwitch: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Picker(L10n.t("模式"), selection: selection) {
            ForEach(PanelAction.allCases, id: \.self) { action in
                Text(action.displayName).tag(action)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    private var selection: Binding<PanelAction> {
        Binding(
            get: { appModel.panelState.lastAction ?? .translate },
            set: { action in
                guard action != appModel.panelState.lastAction else { return }
                appModel.switchAction(to: action)
            }
        )
    }
}

// MARK: - Target language

/// Shows where the translation is going; picking another language retranslates.
private struct TargetLanguageMenu: View {
    @EnvironmentObject private var appModel: AppModel
    var current: TranslationLanguage

    var body: some View {
        Menu {
            ForEach(TranslationLanguage.allCases) { language in
                Button {
                    appModel.retranslate(to: language)
                } label: {
                    if language == current {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            Label(current.displayName, systemImage: "arrow.right")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .controlSize(.small)
        .foregroundStyle(AstryxColor.textSecondary)
        .padding(.horizontal, Spacing.x2)
        .padding(.vertical, 2)
        .background(Capsule(style: .continuous).fill(AstryxColor.overlayHover))
        .fixedSize()
        .help(L10n.t("译文语言"))
        .accessibilityLabel(L10n.f("译文语言：%@", current.displayName))
    }
}

// MARK: - Source text

/// Collapsed: a one-line preview of the selection. Expanded: the full text, selectable.
private struct SourceTextDisclosure: View {
    @EnvironmentObject private var appModel: AppModel
    var text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: Spacing.x1_5) {
                    Text(L10n.t("原文"))
                        .font(.system(size: PanelTokens.metaFontSize, weight: .semibold))
                        .foregroundStyle(AstryxColor.textPrimary)
                    if !isExpanded {
                        Text(preview)
                            .font(.system(size: PanelTokens.metaFontSize))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundStyle(AstryxColor.textSecondary)
                .padding(.horizontal, PanelTokens.cardPadding)
                .padding(.vertical, Spacing.x2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.quietIcon(isStatic: true))
            .accessibilityLabel(isExpanded ? L10n.t("收起原文") : L10n.t("展开原文"))

            if isExpanded {
                Divider()
                    .padding(.horizontal, PanelTokens.cardPadding)
                ScrollView {
                    Text(text)
                        .font(.system(size: PanelTokens.bodyFontSize))
                        .foregroundStyle(AstryxColor.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PanelTokens.cardPadding)
                }
                .frame(maxHeight: PanelTokens.sourceMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelCard(padding: 0)
    }

    private var preview: String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private func toggle() {
        isExpanded.toggle()
        // Let SwiftUI lay out the new size before the window measures it.
        DispatchQueue.main.async { appModel.refitPanel() }
    }
}

// MARK: - Manual input

/// Shown when nothing was selected: type or paste, then translate or explain.
/// ⌘↩ translates, Esc closes; plain Return inserts a newline.
private struct ManualInputView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            if let hint = appModel.panelState.inputHint {
                HStack(spacing: Spacing.x2) {
                    Text(hint)
                        .font(.system(size: PanelTokens.metaFontSize))
                        .foregroundStyle(AstryxColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if appModel.panelState.inputNeedsAccessibility {
                        Button(L10n.t("授权")) { appModel.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }
            }

            ManualInputTextView(
                text: $text,
                placeholder: L10n.t("输入或粘贴要翻译的文字…"),
                fontSize: CGFloat(appModel.settingsStore.translationFontSize),
                onSubmit: { submit(.translate) },
                onEscape: { appModel.closePanel() }
            )
            .frame(minWidth: PanelTokens.minWidth, idealWidth: PanelTokens.idealWidth, minHeight: 96, maxHeight: 160)
            .panelCard()

            HStack(spacing: Spacing.half) {
                PanelIconButton(systemName: "text.viewfinder", label: L10n.t("截图识别")) {
                    appModel.startScreenTextCapture()
                }

                Spacer(minLength: 0)

                QuietLabelButton(title: L10n.t("解释"), systemName: "questionmark.circle") {
                    submit(.explain)
                }
                .disabled(isEmpty)

                QuietLabelButton(title: L10n.t("翻译"), systemName: "character.bubble", shortcut: "⌘↩") {
                    submit(.translate)
                }
                .disabled(isEmpty)
            }
        }
        // The panel was sized for empty content; grow it once the box is in the tree.
        .onAppear {
            DispatchQueue.main.async { appModel.refitPanel() }
        }
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit(_ action: PanelAction) {
        guard !isEmpty else { return }
        appModel.submitManualInput(text, action: action)
    }
}

/// Multi-line AppKit text view: SwiftUI's TextEditor has no placeholder, no
/// ⌘↩ hook, and lets Esc fall into the text system.
private struct ManualInputTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InputTextView()
        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.placeholder = placeholder

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        // Typing should work as soon as the panel appears.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? InputTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: fontSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ManualInputTextView

        init(_ parent: ManualInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true // placeholder visibility
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText() else {
                return false
            }
            parent.onEscape()
            return true
        }
    }

    final class InputTextView: NSTextView {
        weak var coordinator: Coordinator?
        var placeholder = ""

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, !hasMarkedText() {
                coordinator?.parent.text = string
                coordinator?.parent.onSubmit()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, !placeholder.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor,
            ]
            (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height), withAttributes: attributes)
        }
    }
}

// MARK: - History note

/// Marks a result reused from history, with a way to ask the provider again.
private struct HistoryNoteRow: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: Spacing.x1_5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
            Text(L10n.t("来自最近记录，未重新请求"))
                .font(.system(size: PanelTokens.metaFontSize))
            Spacer(minLength: 0)
            PanelIconButton(systemName: "arrow.clockwise", label: L10n.t("重新生成")) {
                appModel.regenerate()
            }
        }
        .foregroundStyle(AstryxColor.textSecondary)
        .padding(.horizontal, Spacing.x1)
    }
}

// MARK: - Follow-ups

private struct FollowUpTurnView: View {
    @EnvironmentObject private var appModel: AppModel
    var turn: FollowUpTurn
    var fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Divider()

            Label {
                Text(turn.question)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.system(size: PanelTokens.bodyFontSize, weight: .medium))
            .foregroundStyle(AstryxColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let error = turn.errorMessage {
                HStack(alignment: .top, spacing: Spacing.x2) {
                    StatusDot(tone: .danger)
                        .padding(.top, 5)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(.system(size: PanelTokens.bodyFontSize))
                        .foregroundStyle(AstryxColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    PanelIconButton(systemName: "arrow.clockwise", label: L10n.t("重试")) {
                        appModel.retryFollowUp(id: turn.id)
                    }
                    .disabled(appModel.panelState.isLoading)
                    // Center the 28pt button on the first line, level with the dot.
                    .alignmentGuide(.top) { $0[VerticalAlignment.center] - 8.5 }
                }
            } else if turn.answer.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.t("正在回答"))
            } else {
                MarkdownTextView(markdown: turn.answer, fontSize: fontSize)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Single-line question field. Return sends, Esc closes the panel; while a request
/// runs, the trailing button stops it.
private struct FollowUpInputBar: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var question = ""

    var body: some View {
        HStack(spacing: Spacing.x1_5) {
            FollowUpTextField(
                text: $question,
                placeholder: L10n.t("继续追问…"),
                onSubmit: submit,
                onEscape: { appModel.closePanel() }
            )
            .frame(maxWidth: .infinity)

            if appModel.panelState.isLoading {
                PanelIconButton(systemName: "stop.circle", label: L10n.t("停止")) {
                    appModel.cancelCurrentRequest()
                }
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: PanelTokens.iconSize, weight: .semibold))
                        .foregroundStyle(canSend ? Color.accentColor : AstryxColor.textDisabled)
                        .panelIconButton()
                }
                .buttonStyle(.quietIcon)
                .disabled(!canSend)
                .help(L10n.t("发送"))
                .accessibilityLabel(L10n.t("发送追问"))
            }
        }
        .padding(.leading, Spacing.x3)
        .padding(.trailing, Spacing.x1)
        .padding(.vertical, Spacing.x1)
        .background(
            RoundedRectangle(cornerRadius: PanelTokens.cardRadius, style: .continuous)
                .fill(PanelTokens.cardFill)
        )
        .hairlineBorder(cornerRadius: PanelTokens.cardRadius)
    }

    private var canSend: Bool {
        appModel.panelState.canAskFollowUp
            && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSend else { return }
        appModel.askFollowUp(question)
        question = ""
    }
}

/// AppKit field so Return/Esc are handled explicitly: SwiftUI's TextField would let
/// Esc fall into the text system, and Return must not fire mid-IME composition.
private struct FollowUpTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: PanelTokens.bodyFontSize)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FollowUpTextField

        init(_ parent: FollowUpTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if textView.hasMarkedText() {
                return false
            }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = textView.string
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

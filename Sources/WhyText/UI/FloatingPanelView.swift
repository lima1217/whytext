import AppKit
import SwiftUI
import WhyTextCore

private enum PanelTokens {
    static let horizontalPadding: CGFloat = Spacing.x4   // 16
    static let bottomPadding: CGFloat = Spacing.x4       // 16
    static let bodyFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    /// Reading column: ~30–35 CJK / ~55–65 Latin glyphs at default 16pt body.
    static let minWidth: CGFloat = 360
    static let idealWidth: CGFloat = 520
    static let minContentHeight: CGFloat = 72
    static let maxHeight: CGFloat = 420
    static let sourceMaxHeight: CGFloat = 120
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
                    Text(noticeText)
                        .font(.system(size: PanelTokens.metaFontSize))
                        .foregroundStyle(AstryxColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.x2)
                        .padding(.vertical, Spacing.x1_5)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                                .fill(AstryxColor.overlayHover)
                        )
                        .padding(.horizontal, PanelTokens.horizontalPadding)
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
                VStack(alignment: .leading, spacing: Spacing.x4) {
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
            }
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
        VStack(alignment: .leading, spacing: Spacing.x2) {
            skeletonBar(widthRatio: 1.0)
            skeletonBar(widthRatio: 0.82)
            skeletonBar(widthRatio: 0.6)
        }
        .frame(
            minWidth: PanelTokens.minWidth,
            idealWidth: PanelTokens.idealWidth,
            minHeight: PanelTokens.minContentHeight,
            alignment: .leading
        )
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

    /// Error: a quiet error card with a status dot + retry. Shake animation on appear.
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            HStack(alignment: .top, spacing: Spacing.x2) {
                StatusDot(tone: .danger)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                Text(message)
                    .foregroundStyle(AstryxColor.textPrimary)
                    .font(.system(size: PanelTokens.bodyFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.x2) {
                Spacer(minLength: 0)

                if appModel.panelState.errorSystemSettingsURL != nil {
                    Button(action: { appModel.openErrorSystemSettings() }) {
                        Label(L10n.t("打开系统设置"), systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                    }
                    .buttonStyle(.quiet)
                }

                if appModel.panelState.errorNeedsSettings {
                    Button(action: { appModel.openSettingsWindow() }) {
                        Label(L10n.t("打开设置"), systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                    }
                    .buttonStyle(.quiet)
                }

                if canRetry {
                    Button(action: { appModel.retryLastAction() }) {
                        Label(L10n.t("重试"), systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                    }
                    .buttonStyle(.quiet(tint: Color.accentColor))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.x3)
        .background(
            RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                .fill(AstryxColor.overlayHover)
        )
        .shadowBorder(cornerRadius: Radius.element)
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
    @State private var isCopyHovered = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: Spacing.x2) {
            if appModel.panelState.lastAction != nil {
                PanelModeSwitch()
            } else if appModel.panelState.phase == .input {
                Text(L10n.t("输入文字"))
                    .font(AstryxFont.bodyMedium)
                    .foregroundStyle(AstryxColor.textSecondary)
            }

            if let target = appModel.panelState.targetLanguage, appModel.panelState.lastAction == .translate {
                TargetLanguageMenu(current: target)
            }

            if shouldShowStatus {
                HStack(spacing: Spacing.x1_5) {
                    statusIcon

                    if let activityTitle {
                        Text(activityTitle)
                            .font(.system(size: PanelTokens.metaFontSize))
                            .foregroundStyle(AstryxColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(headerTitle)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }

            Spacer(minLength: Spacing.x2)

            Button(action: { appModel.togglePanelPinned() }) {
                Image(systemName: appModel.isPanelPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .medium))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(appModel.isPanelPinned ? Color.accentColor : AstryxColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .quietButtonHover()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.quietIcon)
            .help(appModel.isPanelPinned ? L10n.t("取消固定：点击窗口外会关闭") : L10n.t("固定：点击窗口外不关闭"))
            .accessibilityLabel(appModel.isPanelPinned ? L10n.t("取消固定窗口") : L10n.t("固定窗口"))

            Button(action: copyResultIfPossible) {
                ContextualIconSwap(
                    isActive: didCopy,
                    activeSystemName: "checkmark",
                    inactiveSystemName: "doc.on.doc",
                    size: 14
                )
                .foregroundStyle(didCopy ? Tone.success.color : AstryxColor.textSecondary)
                .frame(width: 28, height: 28)
                .background(copyButtonBackground)
                // Grow hit target left/vertical so the glyph stays flush with content trailing.
                .padding(.leading, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .accessibilityLabel(didCopy ? L10n.t("已复制") : L10n.t("复制结果"))
            }
            .buttonStyle(.quietIcon)
            .background(CopyTooltipAnchor(isPresented: isCopyHovered && hasResult, text: L10n.t("复制")))
            .onHover { hovering in
                isCopyHovered = hovering
            }
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

    private var copyButtonBackground: some View {
        RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
            .fill(isCopyHovered ? AstryxColor.overlayHover : Color.clear)
            .animation(AstryxMotion.quick, value: isCopyHovered)
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            if let error = appModel.panelState.errorMessage, !error.isEmpty {
                Image(systemName: Tone.danger.icon)
                    .foregroundStyle(Tone.danger.color)
                    .font(.system(size: 14))
                    .transition(statusIconTransition)
            } else if appModel.panelState.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
                    .transition(statusIconTransition)
            } else if hasResult {
                Image(systemName: Tone.success.icon)
                    .foregroundStyle(Tone.success.color)
                    .font(.system(size: 14))
                    .transition(statusIconTransition)
            }
        }
        .frame(width: 14, height: 14)
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

    /// Only thinking/searching get words; the mode switch already names the action.
    private var activityTitle: String? {
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

private struct CopyTooltipAnchor: NSViewRepresentable {
    var isPresented: Bool
    var text: String

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            CopyTooltipWindow.shared.show(text: text, below: nsView)
        } else {
            CopyTooltipWindow.shared.hide(anchor: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        CopyTooltipWindow.shared.hide(anchor: nsView)
    }
}

@MainActor
private final class CopyTooltipWindow {
    static let shared = CopyTooltipWindow()

    private var panel: NSPanel?
    private weak var anchorView: NSView?

    func show(text: String, below view: NSView) {
        guard let window = view.window else { return }
        anchorView = view

        let size = NSSize(width: 48, height: 30)
        let anchorRect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let origin = NSPoint(
            x: anchorRect.midX - size.width / 2,
            y: anchorRect.minY - size.height - 6
        )

        let panel = panel ?? makePanel(size: size)
        let hosting = NSHostingView(rootView: CopyTooltipView(text: text))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        self.panel = panel
    }

    func hide(anchor view: NSView? = nil) {
        if let view, anchorView !== view { return }
        panel?.orderOut(nil)
        anchorView = nil
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

private struct CopyTooltipView: View {
    var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AstryxColor.textPrimary)
            .padding(.horizontal, Spacing.x2)
            .padding(.vertical, Spacing.x1)
            .background(
                ZStack {
                    if MotionPreference.reduceTransparency {
                        Color(nsColor: .controlBackgroundColor)
                    } else {
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .behindWindow,
                            state: .active,
                            cornerStyle: .continuous(Radius.element)
                        )
                        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.72)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.element, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.5),
                        lineWidth: 0.5
                    )
            )
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
        HStack(spacing: 2) {
            ForEach(PanelAction.allCases, id: \.self) { action in
                segment(action)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                .fill(AstryxColor.overlayHover)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("模式"))
    }

    private func segment(_ action: PanelAction) -> some View {
        let isSelected = appModel.panelState.lastAction == action
        return Button(action: { appModel.switchAction(to: action) }) {
            Text(action.displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AstryxColor.textPrimary : AstryxColor.textSecondary)
                .padding(.horizontal, Spacing.x2)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.element - 2, style: .continuous)
                        .fill(isSelected ? Color(nsColor: .controlBackgroundColor).opacity(0.9) : Color.clear)
                        .shadow(color: isSelected ? AstryxColor.shadow : .clear, radius: 1, y: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.quietIcon)
        .animation(AstryxMotion.quick, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            Text("→ \(current.displayName)")
                .font(.system(size: 12))
                .foregroundStyle(AstryxColor.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
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
        VStack(alignment: .leading, spacing: Spacing.x1_5) {
            Button(action: toggle) {
                HStack(spacing: Spacing.x1_5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(L10n.t("原文"))
                        .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                    if !isExpanded {
                        Text(preview)
                            .font(.system(size: PanelTokens.metaFontSize))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AstryxColor.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.quietIcon(isStatic: true))
            .accessibilityLabel(isExpanded ? L10n.t("收起原文") : L10n.t("展开原文"))

            if isExpanded {
                ScrollView {
                    Text(text)
                        .font(.system(size: PanelTokens.bodyFontSize))
                        .foregroundStyle(AstryxColor.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: PanelTokens.sourceMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.x2)
                .background(
                    RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                        .fill(AstryxColor.overlayHover)
                )
            }
        }
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
                        Button(action: { appModel.openAccessibilitySettings() }) {
                            Text(L10n.t("授权"))
                                .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                        }
                        .buttonStyle(.quiet)
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
            .padding(Spacing.x2)
            .background(
                RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                    .fill(AstryxColor.overlayHover)
            )
            .shadowBorder(cornerRadius: Radius.element)

            HStack(spacing: Spacing.x2) {
                Button(action: { appModel.startScreenTextCapture() }) {
                    Label(L10n.t("截图识别"), systemImage: "text.viewfinder")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                }
                .buttonStyle(.quiet)
                .help(L10n.t("框选屏幕上的区域，识别其中的文字并翻译"))

                Spacer(minLength: 0)

                Button(action: { submit(.explain) }) {
                    Text(L10n.t("解释"))
                        .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                }
                .buttonStyle(.quiet)
                .disabled(isEmpty)

                Button(action: { submit(.translate) }) {
                    Text(L10n.t("翻译  ⌘↩"))
                        .font(.system(size: PanelTokens.metaFontSize, weight: .semibold))
                }
                .buttonStyle(.quiet(tint: Color.accentColor))
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
            Button(action: { appModel.regenerate() }) {
                Label(L10n.t("重新生成"), systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
            }
            .buttonStyle(.quiet(tint: Color.accentColor))
        }
        .foregroundStyle(AstryxColor.textSecondary)
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

            Text(turn.question)
                .font(.system(size: PanelTokens.bodyFontSize, weight: .medium))
                .foregroundStyle(AstryxColor.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
                    Button(action: { appModel.retryFollowUp(id: turn.id) }) {
                        Label(L10n.t("重试"), systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                    }
                    .buttonStyle(.quiet(tint: Color.accentColor))
                    .disabled(appModel.panelState.isLoading)
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
                Button(action: { appModel.cancelCurrentRequest() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AstryxColor.textSecondary)
                }
                .buttonStyle(.quietIcon)
                .help(L10n.t("停止"))
                .accessibilityLabel(L10n.t("停止"))
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(canSend ? Color.accentColor : AstryxColor.textDisabled)
                }
                .buttonStyle(.quietIcon)
                .disabled(!canSend)
                .help(L10n.t("发送"))
                .accessibilityLabel(L10n.t("发送追问"))
            }
        }
        .padding(.leading, Spacing.x2_5)
        .padding(.trailing, Spacing.x1)
        .padding(.vertical, Spacing.x1)
        .background(
            RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                .fill(AstryxColor.overlayHover)
        )
        .shadowBorder(cornerRadius: Radius.element)
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

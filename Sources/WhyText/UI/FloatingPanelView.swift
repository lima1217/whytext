import AppKit
import SwiftUI

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
                Group {
                    content
                }
                .animation(AstryxMotion.smooth, value: contentStateKey)
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
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            errorView(error)
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
        ScrollView {
            MarkdownTextView(markdown: displayText, fontSize: CGFloat(appModel.settingsStore.translationFontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: PanelTokens.minWidth, idealWidth: PanelTokens.idealWidth, maxHeight: PanelTokens.maxHeight)
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
                Text(message)
                    .foregroundStyle(AstryxColor.textPrimary)
                    .font(.system(size: PanelTokens.bodyFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: { appModel.retryLastAction() }) {
                Label("重试", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
            }
            .buttonStyle(.quiet(tint: Color.accentColor))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.x3)
        .background(
            RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                .fill(AstryxColor.overlayHover)
        )
        .shadowBorder(cornerRadius: Radius.element)
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
        let actionName = appModel.panelState.lastAction?.displayName ?? PanelAction.translate.displayName
        if appModel.panelState.isLoading {
            return "正在\(actionName)"
        }
        if hasResult {
            return "\(actionName)结果，点击可复制"
        }
        return "\(actionName)窗口"
    }
}

struct FloatingPanelTitlebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var didCopy = false
    @State private var isCopyHovered = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: Spacing.x2) {
            if shouldShowStatus {
                statusIcon

                Text(headerTitle)
                    .font(AstryxFont.bodyMedium)
                    .foregroundStyle(AstryxColor.textSecondary)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }

            Spacer(minLength: Spacing.x4)

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
                .padding(.leading, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .accessibilityLabel(didCopy ? "已复制" : "复制结果")
            }
            .buttonStyle(.quietIcon)
            .background(CopyTooltipAnchor(isPresented: isCopyHovered, text: "复制"))
            .onHover { hovering in
                isCopyHovered = hovering
            }
            .disabled(appModel.panelState.isLoading || !hasResult)
            .opacity(hasResult ? 1 : 0)
            .help(didCopy ? "已复制" : "复制")
        }
        .frame(height: 32)
        .padding(.trailing, PanelTokens.horizontalPadding)
        .animation(AstryxMotion.smooth, value: shouldShowStatus)
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
                Image(systemName: Tone.warning.icon)
                    .foregroundStyle(Tone.warning.color)
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
        appModel.copyResultPlainTextToPasteboard()
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

    private var headerTitle: String {
        let actionName = appModel.panelState.lastAction?.displayName ?? PanelAction.translate.displayName
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return "\(actionName)失败"
        }
        if appModel.panelState.isLoading {
            return "\(actionName)中"
        }
        return actionName
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

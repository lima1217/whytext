import AppKit
import SwiftUI

private enum PanelTokens {
    static let horizontalPadding: CGFloat = Spacing.x4   // 16
    static let bottomPadding: CGFloat = Spacing.x4       // 16
    static let bodyFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let minWidth: CGFloat = 320
    static let idealWidth: CGFloat = 388
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
                        .transition(.opacity)
                }
            }
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
        } else if appModel.panelState.isLoading && !hasResult {
            loadingView
        } else {
            resultView
        }
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
        .hairlineBorder(cornerRadius: Radius.element)
        .onAppear { triggerShake() }
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
            withAnimation(.astryxSpring(response: 0.15, damping: 0.5)) { shakeOffset = 0 }
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
        if appModel.panelState.isLoading {
            return "正在翻译"
        }
        if hasResult {
            return "翻译结果，点击可复制"
        }
        return "翻译窗口"
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
            }

            Spacer(minLength: Spacing.x4)

            Button(action: copyResultIfPossible) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .accessibilityLabel(didCopy ? "已复制" : "复制译文")
            }
            .buttonStyle(.plain)
            .foregroundStyle(didCopy ? Tone.success.color : AstryxColor.textSecondary)
            .background(copyButtonBackground)
            .background(CopyTooltipAnchor(isPresented: isCopyHovered, text: "复制"))
            .contentShape(Rectangle())
            .onHover { hovering in
                isCopyHovered = hovering
            }
            .disabled(appModel.panelState.isLoading || !hasResult)
            .opacity(hasResult ? 1 : 0)
            .help(didCopy ? "已复制" : "复制")
        }
        .frame(height: 32)
        .padding(.trailing, PanelTokens.horizontalPadding)
        .onDisappear { copyResetTask?.cancel() }
    }

    private var copyButtonBackground: some View {
        RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
            .fill(isCopyHovered ? AstryxColor.overlayHover : Color.clear)
            .shadow(
                color: isCopyHovered ? Color.black.opacity(0.18) : Color.clear,
                radius: 10,
                x: 0,
                y: 3
            )
            .animation(AstryxMotion.quick, value: isCopyHovered)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            Image(systemName: Tone.warning.icon)
                .foregroundStyle(Tone.warning.color)
                .font(.system(size: 14))
        } else if appModel.panelState.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        } else if hasResult {
            Image(systemName: Tone.success.icon)
                .foregroundStyle(Tone.success.color)
                .font(.system(size: 14))
        }
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
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return "翻译失败"
        }
        if appModel.panelState.isLoading {
            return "翻译中"
        }
        return "翻译"
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
        panel.contentView = NSHostingView(rootView: CopyTooltipView(text: text))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
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
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

private struct CopyTooltipView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AstryxColor.textPrimary)
            .padding(.horizontal, Spacing.x2)
            .padding(.vertical, Spacing.x1)
            .background(
                RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 3)
            )
    }
}

// MARK: - Skeleton shimmer

/// Sweeps a faint highlight across a skeleton bar to suggest in-progress content.
private struct SkeletonShimmerModifier: ViewModifier, Animatable {
    let width: CGFloat
    @State private var offset: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .offset(x: offset * width)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.1)
                    .repeatForever(autoreverses: false)
                ) {
                    offset = 1.6
                }
            }
    }
}

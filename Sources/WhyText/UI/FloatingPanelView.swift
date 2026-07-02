import SwiftUI

private enum PanelTokens {
    static let horizontalPadding: CGFloat = Spacing.x4   // 16
    static let topPadding: CGFloat = Spacing.x3          // 12
    static let bottomPadding: CGFloat = Spacing.x4       // 16
    static let bodyFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let minWidth: CGFloat = 320
    static let idealWidth: CGFloat = 388
    static let minContentHeight: CGFloat = 72
    static let maxHeight: CGFloat = 420
    static let progressHeight: CGFloat = 2
}

struct FloatingPanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var shakeOffset: CGFloat = 0
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header

            progressBar
                .padding(.top, 6)
                .padding(.bottom, 8)

            Group {
                content
            }
            .animation(AstryxMotion.smooth, value: contentStateKey)
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
        .background(Color(nsColor: .windowBackgroundColor))
        .offset(x: shakeOffset)
        .onExitCommand { appModel.closePanel() }
        .onDisappear { copyResetTask?.cancel() }
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: Spacing.x2) {
            statusIcon

            Text(headerTitle)
                .font(AstryxFont.bodyMedium)
                .foregroundStyle(AstryxColor.textSecondary)

            Spacer(minLength: Spacing.x4)

            Button(action: copyResultIfPossible) {
                Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: PanelTokens.bodyFontSize, weight: .medium))
            }
            .buttonStyle(.quiet(tint: didCopy ? Tone.success.color : AstryxColor.textSecondary))
            .disabled(appModel.panelState.isLoading || !hasResult)
            .opacity(hasResult ? 1 : 0)
            .help(didCopy ? "已复制" : "复制译文")
        }
        .padding(.top, PanelTokens.topPadding)
        .padding(.horizontal, PanelTokens.horizontalPadding)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            Image(systemName: Tone.warning.icon)
                .foregroundStyle(Tone.warning.color)
                .font(.system(size: 14))
        } else if hasResult {
            Image(systemName: Tone.success.icon)
                .foregroundStyle(Tone.success.color)
                .font(.system(size: 14))
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        }
    }

    // MARK: - Progress Bar

    /// A thin, Safari-style progress line at the top of the panel.
    /// Visible only during loading. The streaming text itself is the real progress.
    private var progressBar: some View {
        GeometryReader { geo in
            if appModel.panelState.isLoading {
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.35), Color.accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.3, height: PanelTokens.progressHeight)
                    .modifier(IndeterminateProgressModifier(width: geo.size.width))
            }
        }
        .frame(height: PanelTokens.progressHeight)
        .padding(.horizontal, PanelTokens.horizontalPadding)
        .opacity(appModel.panelState.isLoading ? 1 : 0)
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
            Text("翻译中…")
                .font(.system(size: PanelTokens.bodyFontSize))
                .foregroundStyle(AstryxColor.textSecondary)

            // A quiet skeleton bar suggesting in-progress content.
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

    private var headerTitle: String {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            return "翻译失败"
        }
        if hasResult {
            return "翻译结果"
        }
        return "翻译"
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

// MARK: - Indeterminate Progress Animation

/// Slides a highlight bar back and forth continuously.
private struct IndeterminateProgressModifier: ViewModifier, Animatable {
    let width: CGFloat
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                withAnimation(
                    AstryxMotion.smooth
                    .repeatForever(autoreverses: true)
                ) {
                    offset = width * 0.6
                }
            }
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

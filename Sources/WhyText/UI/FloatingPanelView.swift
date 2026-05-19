import SwiftUI

private enum PanelTokens {
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 16
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
            .animation(.easeInOut(duration: 0.18), value: contentStateKey)
            .padding(.horizontal, PanelTokens.horizontalPadding)
            .padding(.bottom, PanelTokens.bottomPadding)

            if let noticeText, !noticeText.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.05))
                    .padding(.horizontal, PanelTokens.horizontalPadding)

                Text(noticeText)
                    .font(.system(size: PanelTokens.metaFontSize))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PanelTokens.horizontalPadding)
                    .padding(.vertical, 8)
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
        HStack(spacing: 10) {
            statusIcon

            Text(headerTitle)
                .font(.system(size: PanelTokens.bodyFontSize, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Button(action: copyResultIfPossible) {
                Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: PanelTokens.bodyFontSize, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(didCopy ? Color.green : Color.secondary)
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
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 22))
        } else if hasResult {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 22))
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
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
                    .frame(width: geo.size.width * 0.4, height: PanelTokens.progressHeight)
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
        Text("翻译中...")
            .font(.system(size: PanelTokens.bodyFontSize))
            .foregroundStyle(.tertiary)
            .frame(
                minWidth: PanelTokens.minWidth,
                idealWidth: PanelTokens.idealWidth,
                minHeight: PanelTokens.minContentHeight,
                alignment: .leading
            )
    }

    /// Error: subtle message + tap-to-retry. Shake animation on appear.
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .foregroundStyle(.secondary)
                .font(.system(size: PanelTokens.bodyFontSize))

            Button(action: { appModel.retryLastAction() }) {
                Text("重试")
                    .font(.system(size: PanelTokens.metaFontSize, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .onAppear { triggerShake() }
    }

    // MARK: - Shake Animation

    private func triggerShake() {
        withAnimation(.default) { shakeOffset = 6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = -5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = -2 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { shakeOffset = 0 }
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
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = width * 0.6
                }
            }
    }
}

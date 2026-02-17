import SwiftUI

private enum PanelTokens {
    static let cornerRadius: CGFloat = 14
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 14
    static let bodyFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let minWidth: CGFloat = 320
    static let idealWidth: CGFloat = 388
    static let maxHeight: CGFloat = 420
    static let shadowRadius: CGFloat = 20
    static let shadowY: CGFloat = 8
    static let progressHeight: CGFloat = 2
}

struct FloatingPanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Thin progress bar — the only loading indicator
                progressBar
                    .padding(.bottom, 6)

                // Content area
                Group {
                    content
                }
                .animation(.easeInOut(duration: 0.2), value: contentStateKey)
                .padding(.horizontal, PanelTokens.horizontalPadding)
                .padding(.bottom, PanelTokens.verticalPadding)

                // Subtle notice (e.g. truncation info) — only when done
                if let noticeText, !noticeText.isEmpty {
                    Divider()
                        .overlay(Color.primary.opacity(0.04))
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
            .padding(.top, PanelTokens.verticalPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: PanelTokens.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PanelTokens.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: PanelTokens.shadowRadius, x: 0, y: PanelTokens.shadowY)
        .offset(x: shakeOffset)
        .onExitCommand { appModel.closePanel() }
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
                            colors: [Color.accentColor.opacity(0.5), Color.accentColor],
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
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = appModel.panelState.errorMessage, !error.isEmpty {
            errorView(error)
        } else if appModel.panelState.isLoading && !hasResult {
            // No text yet — just show a quiet placeholder.
            // The progress bar above does the talking.
            Text("")
                .frame(minWidth: PanelTokens.minWidth, idealWidth: PanelTokens.idealWidth)
                .frame(height: 32)
        } else {
            resultView
        }
    }

    private var resultView: some View {
        ScrollView {
            MarkdownTextView(markdown: displayText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: PanelTokens.minWidth, idealWidth: PanelTokens.idealWidth, maxHeight: PanelTokens.maxHeight)
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

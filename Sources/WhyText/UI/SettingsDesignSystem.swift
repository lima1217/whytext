import SwiftUI
import WhyTextCore

/// Shared layout constants for the settings window.
enum SettingsUI {
    static let sidebarWidth: CGFloat = 212
    static let headerHeight: CGFloat = 52
    static let fieldRadius: CGFloat = Radius.element
    static let fieldBackground = AstryxColor.overlayHover
}

// MARK: - Panes

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case translation
    case providers
    case prompts
    case memory
    case permissions
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L10n.t("通用")
        case .shortcuts: L10n.t("快捷键")
        case .translation: L10n.t("翻译")
        case .providers: L10n.t("服务商")
        case .prompts: L10n.t("提示词")
        case .memory: L10n.t("阅读记忆")
        case .permissions: L10n.t("权限")
        case .updates: L10n.t("更新")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .translation: "character.bubble.fill"
        case .providers: "server.rack"
        case .prompts: "text.quote"
        case .memory: "books.vertical.fill"
        case .permissions: "hand.raised.fill"
        case .updates: "arrow.down.circle.fill"
        }
    }
}

/// A bare glyph in a fixed-width slot, so row titles line up. No colored tile:
/// the page keeps a single accent, which is the selected row itself.
struct PaneIcon: View {
    var pane: SettingsPane
    var size: CGFloat = 22
    var isSelected = false

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: size * 0.62, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : AstryxColor.textSecondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Page scaffolding

/// A settings page: a title bar aligned with the window's traffic lights over a grouped form.
struct SettingsPage<Content: View>: View {
    var pane: SettingsPane
    let content: Content

    init(_ pane: SettingsPane, @ViewBuilder content: () -> Content) {
        self.pane = pane
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.x2_5) {
                Text(pane.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AstryxColor.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Spacing.x6)
            .frame(height: SettingsUI.headerHeight)

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Row label with an optional secondary line, for use as a `LabeledContent` / `Toggle` label.
struct SettingsRowLabel: View {
    var title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.half) {
            Text(title)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AstryxFont.captionM)
                    .foregroundStyle(AstryxColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Shared pieces

/// Setup status: quiet text with a check when done, the accent color when it needs doing.
/// One emphasis color per page, so "ready" never competes with "needs you".
struct SetupStatus: View {
    var text: String
    var ready: Bool

    var body: some View {
        HStack(spacing: Spacing.x1) {
            if ready {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(AstryxColor.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(AstryxFont.captionM)
        }
        .foregroundStyle(ready ? AstryxColor.textSecondary : AstryxColor.accentText)
        .fixedSize()
    }
}

struct StatusBadge: View {
    var text: String
    var tone: Tone

    var body: some View {
        Label(text, systemImage: tone.icon)
            .font(.system(size: 11, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tone.color)
            .padding(.horizontal, Spacing.x2)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.mutedFill)
            )
            .fixedSize()
    }
}

struct CaptionText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(AstryxFont.captionM)
            .foregroundStyle(AstryxColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Inset well used for monospaced reports and editors inside a form row.
extension View {
    func settingsWell(padding: CGFloat = Spacing.x2_5) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: SettingsUI.fieldRadius, style: .continuous)
                    .fill(SettingsUI.fieldBackground)
            )
            .hairlineBorder(cornerRadius: SettingsUI.fieldRadius)
    }
}

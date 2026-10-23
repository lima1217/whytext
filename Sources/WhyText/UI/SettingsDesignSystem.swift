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
        case .translation: L10n.t("翻译方向")
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

    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .shortcuts: Color(nsColor: .systemBlue)
        case .translation: Color(nsColor: .systemGreen)
        case .providers: Color(nsColor: .systemPurple)
        case .prompts: Color(nsColor: .systemOrange)
        case .memory: Color(nsColor: .systemTeal)
        case .permissions: Color(nsColor: .systemIndigo)
        case .updates: Color(nsColor: .systemPink)
        }
    }
}

/// Rounded-square glyph tile in the style of System Settings.
struct PaneIcon: View {
    var pane: SettingsPane
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(pane.tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
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

import SwiftUI

enum SettingsUI {
    static let contentWidth: CGFloat = 640
    static let pagePadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 14
    static let fieldSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 12
    static let labelWidth: CGFloat = 92
    static let captionSize: CGFloat = 12

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let fieldBackground = Color.primary.opacity(0.045)
}

struct SettingsPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsUI.sectionSpacing) {
                content
            }
            .frame(maxWidth: SettingsUI.contentWidth, alignment: .leading)
            .padding(SettingsUI.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsCard<Content: View>: View {
    var title: String
    var subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: SettingsUI.captionSize))
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsUI.cornerRadius, style: .continuous)
                .fill(SettingsUI.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUI.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}

struct StatusBadge: View {
    enum Tone {
        case success
        case warning
        case neutral
        case danger

        var color: Color {
            switch self {
            case .success: .green
            case .warning: .orange
            case .neutral: .secondary
            case .danger: .red
            }
        }

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .neutral: "circle.fill"
            case .danger: "xmark.circle.fill"
            }
        }
    }

    var text: String
    var tone: Tone

    var body: some View {
        Label(text, systemImage: tone.symbol)
            .font(.system(size: 11, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.color.opacity(0.14))
            )
    }
}

struct CaptionText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: SettingsUI.captionSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct LabeledSettingsField<Field: View>: View {
    var title: String
    let field: Field

    init(_ title: String, @ViewBuilder field: () -> Field) {
        self.title = title
        self.field = field()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsUI.fieldSpacing) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: SettingsUI.labelWidth, alignment: .leading)

            field
        }
    }
}

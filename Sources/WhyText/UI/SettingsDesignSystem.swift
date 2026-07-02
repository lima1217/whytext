import SwiftUI

/// Shared layout constants for the settings windows.
/// Thin wrappers over the project-wide design tokens (`Spacing`, `Radius`, `AstryxFont`).
enum SettingsUI {
    static let contentWidth: CGFloat = 640
    static let pagePadding: CGFloat = Spacing.x6        // 24
    static let sectionSpacing: CGFloat = Spacing.x3_5    // 14
    static let fieldSpacing: CGFloat = Spacing.x3        // 12
    static let cornerRadius: CGFloat = Radius.container  // 12
    static let labelWidth: CGFloat = 92
    static let captionSize: CGFloat = 12                 // kept for monospaced numeric sizing

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let fieldBackground = AstryxColor.overlayHover
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
        VStack(alignment: .leading, spacing: Spacing.x4) {
            VStack(alignment: .leading, spacing: Spacing.half) {
                Text(title)
                    .font(AstryxFont.bodySemibold)
                    .foregroundStyle(AstryxColor.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AstryxFont.captionM)
                        .foregroundStyle(AstryxColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(Spacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: SettingsUI.cornerRadius, fill: SettingsUI.cardBackground)
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
            .padding(.horizontal, Spacing.x2_5)
            .padding(.vertical, Spacing.x1)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.mutedFill)
            )
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
                .font(AstryxFont.body)
                .foregroundStyle(AstryxColor.textSecondary)
                .frame(width: SettingsUI.labelWidth, alignment: .leading)

            field
        }
    }
}

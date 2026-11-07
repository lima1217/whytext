import SwiftUI
import WhyTextCore

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $appModel.settingsPane)
                .frame(width: SettingsUI.sidebarWidth)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Rebuild every page when the interface language changes; child views that
        // only take bindings wouldn't otherwise re-render their own strings.
        .id(appModel.settingsStore.interfaceLanguage)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 600)
        .ignoresSafeArea()
        .tint(AstryxColor.accent)
        .environmentObject(appModel)
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.settingsPane {
        case .general: GeneralSettingsView(selection: $appModel.settingsPane)
        case .shortcuts: ShortcutsSettingsView()
        case .translation: TranslationSettingsView()
        case .providers: ProvidersSettingsView()
        case .prompts: PromptsSettingsView()
        case .memory: MemorySettingsView()
        case .permissions: PermissionsSettingsView()
        case .updates: UpdatesSettingsView()
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the traffic lights; the window uses a full-size content view.
            Color.clear.frame(height: SettingsUI.headerHeight)

            HStack(spacing: Spacing.x2_5) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("WhyText")
                        .font(AstryxFont.bodySemibold)
                        .foregroundStyle(AstryxColor.textPrimary)
                    Text(appModel.updateChecker.currentVersion?.description ?? L10n.t("开发版"))
                        .font(AstryxFont.captionM)
                        .monospacedDigit()
                        .foregroundStyle(AstryxColor.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.x4)
            .padding(.bottom, Spacing.x4)

            VStack(spacing: Spacing.half) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(
                        pane: pane,
                        isSelected: pane == selection,
                        attention: attention(for: pane)
                    ) {
                        selection = pane
                    }
                }
            }
            .padding(.horizontal, Spacing.x2_5)

            Spacer()
        }
        // Flat warm surface: no material, so the sidebar reads the same over any wallpaper.
        .background(AstryxColor.sidebarBackground)
    }

    /// Panes that need the user's attention get a dot in the sidebar.
    private func attention(for pane: SettingsPane) -> Tone? {
        switch pane {
        case .shortcuts:
            if appModel.hotKeyIssue?.isBlocking == true || appModel.ocrHotKeyIssue?.isBlocking == true { return .danger }
            if appModel.settingsStore.hotKeyShortcut == nil || appModel.hotKeyIssue != nil || appModel.ocrHotKeyIssue != nil { return .warning }
            return nil
        case .providers:
            return appModel.hasUsableProvider ? nil : .warning
        case .prompts:
            let store = appModel.settingsStore
            let valid = store.translatePromptTemplate.contains("{{text}}") && store.explainPromptTemplate.contains("{{text}}")
            return valid ? nil : .danger
        case .permissions:
            return appModel.accessibilityStatus() == .trusted ? nil : .warning
        case .updates:
            return appModel.updateChecker.availableUpdate != nil ? .success : nil
        case .general, .translation, .memory:
            return nil
        }
    }
}

private struct SidebarRow: View {
    var pane: SettingsPane
    var isSelected: Bool
    var attention: Tone?
    var action: () -> Void

    @State private var isHovered = false


    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.x2) {
                PaneIcon(pane: pane, isSelected: isSelected)
                Text(pane.title)
                    .font(AstryxFont.body)
                    .foregroundStyle(isSelected ? Color.white : AstryxColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let attention {
                    Circle()
                        .fill(isSelected ? Color.white : AstryxColor.accent)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Spacing.x1_5)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.element - 2, style: .continuous)
                    .fill(isSelected ? AstryxColor.accent : (isHovered ? AstryxColor.overlayHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(attention == nil ? "" : L10n.t("需要处理"))
    }
}

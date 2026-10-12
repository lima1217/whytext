import SwiftUI
import WhyTextCore

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L10n.t("通用"), systemImage: "gearshape") }

            ProvidersSettingsView()
                .tabItem { Label(L10n.t("服务商"), systemImage: "network") }

            PromptsSettingsView()
                .tabItem { Label(L10n.t("提示词"), systemImage: "text.quote") }
        }
        // Rebuild every page when the interface language changes; child views that
        // only take bindings wouldn't otherwise re-render their own strings.
        .id(appModel.settingsStore.interfaceLanguage)
        .padding(Spacing.x4)
        .frame(width: 720, height: 560)
        .environmentObject(appModel)
    }
}

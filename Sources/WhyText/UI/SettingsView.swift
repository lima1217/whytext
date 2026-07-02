import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }

            ProvidersSettingsView()
                .tabItem { Label("服务商", systemImage: "network") }

            PromptsSettingsView()
                .tabItem { Label("提示词", systemImage: "text.quote") }
        }
        .padding(Spacing.x4)
        .frame(width: 720, height: 560)
        .environmentObject(appModel)
    }
}

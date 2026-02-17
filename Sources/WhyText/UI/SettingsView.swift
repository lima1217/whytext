import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }

            ProvidersSettingsView()
                .tabItem { Label("Provider", systemImage: "network") }

            PromptsSettingsView()
                .tabItem { Label("提示词", systemImage: "text.quote") }
        }
        .padding(16)
        .frame(width: 680, height: 480)
        .environmentObject(appModel)
    }
}

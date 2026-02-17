import AppKit
import SwiftUI

@main
struct WhyTextApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("WhyText", systemImage: "globe") {
            MenuBarView()
                .environmentObject(appModel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}

import AppKit
import SwiftUI

@main
struct WhyTextApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if UISnapshotHarness.isActive {
            let model = UISnapshotHarness.makeModel()
            _appModel = StateObject(wrappedValue: model)
            DispatchQueue.main.async { UISnapshotHarness.run(model: model) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appModel)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}

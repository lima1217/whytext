import Foundation

/// Version-specific glue for `UISnapshotHarness`.
@MainActor
enum UISnapshotHooks {
    static func select(_ pane: SettingsPane, in model: AppModel) {
        model.settingsPane = pane
    }
}

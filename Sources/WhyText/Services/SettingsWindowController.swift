import AppKit
import SwiftUI
import WhyTextCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    private static var title: String { L10n.t("WhyText 设置") }

    /// Re-applies the window title after the interface language changes.
    func refreshTitle() {
        window?.title = Self.title
    }

    func show<V: View>(@ViewBuilder content: () -> V) {
        let rootView = AnyView(content())

        if let window {
            (window.contentView as? NSHostingView<AnyView>)?.rootView = rootView
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = hosting
        window.setFrameAutosaveName("WhyText.SettingsWindow")

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Bind to a `let` first: older compilers reject capturing the weak
            // `self` var in the concurrently-executing Task closure.
            guard let self else { return }
            Task { @MainActor in
                self.window = nil
            }
        }

        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

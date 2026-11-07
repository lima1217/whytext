import AppKit
import SwiftUI
import WhyTextCore

/// Renders every settings page and the main panel states to PNGs, then quits.
/// Only runs when `WHYTEXT_SNAPSHOT_DIR` is set; uses throwaway stores so the
/// user's real settings, history and API keys are never read or shown.
///
///     WHYTEXT_SNAPSHOT_DIR=/tmp/shots .build/debug/WhyText
///
/// Optional: `WHYTEXT_SNAPSHOT_LANGS=zh-Hans,en`, `WHYTEXT_SNAPSHOT_SIZES=760x520,820x600`,
/// `WHYTEXT_SNAPSHOT_APPEARANCES=light,dark`, `WHYTEXT_SNAPSHOT_PSEUDO=1` (stretched English).
@MainActor
enum UISnapshotHarness {
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["WHYTEXT_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static var isActive: Bool { outputDirectory != nil }

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static func makeModel() -> AppModel {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("whytext-snapshot-\(UUID().uuidString)")
        let store = SettingsStore(apiKeychainStore: APIKeychainStore(service: "WhyText.UISnapshot"))
        return AppModel(
            settingsStore: store,
            historyStore: HistoryStore(fileURL: nil),
            readingMemory: ReadingMemoryStore(directory: tmp)
        )
    }

    static func run(model: AppModel) {
        guard let out = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let languages = (env["WHYTEXT_SNAPSHOT_LANGS"] ?? "zh-Hans,zh-Hant,en,ja,ko")
            .split(separator: ",").compactMap { InterfaceLanguage(rawValue: String($0)) }
        let sizes: [NSSize] = (env["WHYTEXT_SNAPSHOT_SIZES"] ?? "760x520,820x600")
            .split(separator: ",").compactMap { part in
                let wh = part.split(separator: "x").compactMap { Double($0) }
                return wh.count == 2 ? NSSize(width: wh[0], height: wh[1]) : nil
            }
        let appearances = (env["WHYTEXT_SNAPSHOT_APPEARANCES"] ?? "light,dark").split(separator: ",").map(String.init)
        let pseudo = env["WHYTEXT_SNAPSHOT_PSEUDO"] == "1"

        var runs: [(InterfaceLanguage, String)] = languages.map { ($0, $0.rawValue) }
        if pseudo { runs.append((.english, "pseudo")) }

        for (language, tag) in runs {
            model.settingsStore.interfaceLanguage = language
            L10n.language = language
            L10n.pseudoLocalize = tag == "pseudo"
            for appearance in appearances {
                let nsAppearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                for size in sizes {
                    for pane in SettingsPane.allCases {
                        UISnapshotHooks.select(pane, in: model)
                        let view = SettingsView().environmentObject(model)
                        capture(view, size: size, appearance: nsAppearance,
                                to: out.appendingPathComponent("settings-\(pane.rawValue)-\(tag)-\(appearance)-\(Int(size.width))x\(Int(size.height)).png"))
                    }
                }
                let bubble = SelectionBubbleBar(onTranslate: {}, onExplain: {}, onHoverChange: { _ in })
                    .padding(Spacing.x6)
                    .background(Color(nsColor: .textBackgroundColor))
                capture(bubble, size: nil, appearance: nsAppearance,
                        to: out.appendingPathComponent("bubble-\(tag)-\(appearance).png"))

                for (name, state) in panelStates() {
                    model.panelState = state
                    let view = VStack(spacing: 0) {
                        FloatingPanelTitlebarView().padding(.leading, 76)
                        FloatingPanelView()
                    }
                    .frame(width: 520)
                    .fixedSize(horizontal: false, vertical: true)
                    .environmentObject(model)
                    capture(view, size: nil, appearance: nsAppearance,
                            to: out.appendingPathComponent("panel-\(name)-\(tag)-\(appearance).png"))
                }
            }
        }
        L10n.pseudoLocalize = false
        NSApp.terminate(nil)
    }

    private static func panelStates() -> [(String, PanelState)] {
        var result = PanelState()
        result.selectedText = "Serendipity is the occurrence of events by chance in a happy or beneficial way."
        result.resultText = "**意外之喜**：指偶然发生、结果令人愉快或有益的事情。"
        result.lastAction = .translate
        result.lastInputText = result.selectedText
        result.targetLanguage = .simplifiedChinese
        result.phase = .result
        result.noticeMessage = L10n.f("第 %@ 次查这个词", 1234.formatted())

        var error = PanelState()
        error.selectedText = result.selectedText
        error.lastAction = .translate
        error.lastInputText = result.selectedText
        error.targetLanguage = .simplifiedChinese
        error.phase = .result
        error.errorMessage = L10n.t("请先在设置中填写 API Key")
        error.errorNeedsSettings = true

        var input = PanelState()
        input.phase = .input
        input.inputHint = L10n.t("未授权辅助功能，读不到选中文本。可以直接输入或粘贴：")
        input.inputNeedsAccessibility = true

        return [("result", result), ("error", error), ("input", input)]
    }

    private static func capture<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance?, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        let frameSize = size ?? hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: frameSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = appearance
        window.contentView = hosting
        window.setContentSize(frameSize)
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle (first layout pass, async onAppear work).
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            write(NSBitmapImageRep(cgImage: cg), to: url)
        } else if let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) {
            hosting.cacheDisplay(in: bounds, to: rep)
            write(rep, to: url)
        }
        // Detach the view so old windows stop observing the shared model.
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}

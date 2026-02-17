import AppKit
import SwiftUI

struct HotKeyRecorderView: View {
    @Binding var shortcut: KeyboardShortcut?
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut?.displayString ?? "未设置")
                .frame(minWidth: 140, alignment: .leading)
                .font(.system(.body, design: .monospaced))

            Button(isRecording ? "按键中…" : "录制") {
                isRecording.toggle()
            }

            Button("清除") {
                shortcut = nil
                isRecording = false
            }
            .disabled(shortcut == nil)

            if isRecording {
                KeyCaptureView { captured in
                    shortcut = captured
                    isRecording = false
                } onCancel: {
                    isRecording = false
                }
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct KeyCaptureView: NSViewRepresentable {
    var onCapture: (KeyboardShortcut) -> Void
    var onCancel: () -> Void

    init(onCapture: @escaping (KeyboardShortcut) -> Void, onCancel: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onCapture: ((KeyboardShortcut) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if flags.isEmpty {
            // Avoid registering plain keys as global hotkeys.
            NSSound.beep()
            return
        }

        let shortcut = KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifierFlagsRaw: flags.rawValue
        )
        onCapture?(shortcut)
    }
}


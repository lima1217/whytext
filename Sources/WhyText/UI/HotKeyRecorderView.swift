import AppKit
import SwiftUI
import WhyTextCore

struct HotKeyRecorderView: View {
    @Binding var shortcut: KeyboardShortcut?
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: Spacing.x2_5) {
            Text(shortcut?.displayString ?? L10n.t("未设置"))
                .font(AstryxFont.bodyMono)
                .foregroundStyle(shortcut == nil ? AstryxColor.textSecondary : AstryxColor.textPrimary)
                .padding(.horizontal, Spacing.x2_5)
                .padding(.vertical, Spacing.x1_5)
                .frame(minWidth: 142, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
                        .fill(SettingsUI.fieldBackground)
                )
                .shadowBorder(cornerRadius: Radius.element)
                .accessibilityLabel(L10n.t("当前快捷键"))
                .accessibilityValue(shortcut?.displayString ?? L10n.t("未设置"))

            Button {
                isRecording.toggle()
            } label: {
                Label(isRecording ? L10n.t("按键中…") : L10n.t("录制"), systemImage: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
            }
            .buttonStyle(.quiet)
            .accessibilityLabel(isRecording ? L10n.t("正在录制快捷键，请按下组合键，按 Esc 取消") : L10n.t("录制快捷键"))

            Button {
                shortcut = nil
                isRecording = false
            } label: {
                Label(L10n.t("清除"), systemImage: "xmark")
            }
            .buttonStyle(.quiet)
            .disabled(shortcut == nil)
            .accessibilityLabel(L10n.t("清除快捷键"))

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
        .accessibilityElement(children: .contain)
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

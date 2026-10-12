import AppKit
import Carbon
import Foundation

final class HotKeyManager {
    var onPressed: (() -> Void)?

    private let hotKeyID: EventHotKeyID
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Each manager owns one shortcut; give each a distinct `id`.
    init(id: UInt32 = 1) {
        hotKeyID = EventHotKeyID(signature: 0x57485458, id: id) // "WHTX"
    }

    func register(shortcut: KeyboardShortcut) throws {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard hotKeyID.signature == manager.hotKeyID.signature, hotKeyID.id == manager.hotKeyID.id else {
                    // Another manager's shortcut: let the event reach its handler.
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async {
                    manager.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.failedToInstallHandler
        }

        let modifiers = carbonModifiers(from: shortcut.modifierFlags)
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr, let ref else {
            throw HotKeyError.failedToRegister
        }

        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}

enum HotKeyError: LocalizedError {
    case failedToInstallHandler
    case failedToRegister

    var errorDescription: String? {
        switch self {
        case .failedToInstallHandler:
            "无法安装热键事件监听"
        case .failedToRegister:
            "无法注册全局快捷键（可能已被其他应用占用）"
        }
    }
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    return modifiers
}


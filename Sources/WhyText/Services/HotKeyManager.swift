import AppKit
import Carbon
import Foundation
import WhyTextCore

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

/// Why a configured shortcut may not work.
///
/// Registration doesn't fail when another app or macOS already uses a combination
/// (Carbon only rejects duplicates within this process), so conflicts with other
/// apps can't be detected. Enabled macOS shortcuts can be, via `CopySymbolicHotKeys`.
enum HotKeyIssue: Equatable {
    case registrationFailed(KeyboardShortcut)
    case sameAsTranslateShortcut
    /// Registered, but macOS handles the combination first.
    case conflictsWithSystemShortcut(KeyboardShortcut)

    /// The shortcut is definitely not active (as opposed to possibly shadowed).
    var isBlocking: Bool {
        switch self {
        case .registrationFailed, .sameAsTranslateShortcut: true
        case .conflictsWithSystemShortcut: false
        }
    }

    var message: String {
        switch self {
        case .registrationFailed(let shortcut):
            L10n.f("%@ 无法注册，请换一个组合键。", shortcut.displayString)
        case .sameAsTranslateShortcut:
            L10n.t("与「翻译选中文本」的快捷键相同，请换一个组合键。")
        case .conflictsWithSystemShortcut(let shortcut):
            L10n.f("%@ 已被 macOS 系统快捷键使用（例如 Spotlight 或切换输入法），按下时会先触发系统功能。请换一个组合键，或在「系统设置 → 键盘 → 键盘快捷键」中关闭对应的系统快捷键。", shortcut.displayString)
        }
    }
}

enum HotKeyError: LocalizedError {
    case failedToInstallHandler
    case failedToRegister

    var errorDescription: String? {
        switch self {
        case .failedToInstallHandler:
            L10n.t("无法安装热键事件监听")
        case .failedToRegister:
            L10n.t("无法注册全局快捷键（可能已被其他应用占用）")
        }
    }
}

extension HotKeyManager {
    /// Whether an enabled macOS shortcut (System Settings → Keyboard → Keyboard
    /// Shortcuts) uses exactly this combination.
    static func conflictsWithSystemShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }

        let standard = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let modifiers = carbonModifiers(from: shortcut.modifierFlags)
        return entries.contains { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let raw = entry[kHISymbolicHotKeyModifiers as String] as? Int else {
                return false
            }
            // Entries that also need fn (or another non-standard bit) don't fire without it.
            let systemModifiers = UInt32(truncatingIfNeeded: raw)
            return UInt32(code) == shortcut.keyCode
                && systemModifiers & ~standard == 0
                && systemModifiers == modifiers
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


import AppKit
import Carbon.HIToolbox
import Combine

private let nookShortcutSignature: OSType = 0x4E4F4F4B // NOOK
private let nookShortcutHotKeyIDValue: UInt32 = 1

enum NookShortcutIssue: Equatable {
    case modifierRequired
    case systemConflict(String)
    case unavailable
}

struct NookShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let carbonModifiers: UInt32

    static let defaultValue = NookShortcut(
        keyCode: 45,
        carbonModifiers: UInt32(cmdKey) | UInt32(optionKey)
    )

    private static let supportedModifiers = UInt32(cmdKey)
        | UInt32(optionKey)
        | UInt32(controlKey)
        | UInt32(shiftKey)

    init(keyCode: UInt16, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & Self.supportedModifiers
    }

    init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return nil }
        self.init(keyCode: event.keyCode, carbonModifiers: modifiers)
    }

    var issue: NookShortcutIssue? {
        guard carbonModifiers != 0 else { return .modifierRequired }

        let command = UInt32(cmdKey)
        let option = UInt32(optionKey)
        let control = UInt32(controlKey)
        let shift = UInt32(shiftKey)

        if matches(keyCode: 49, modifiers: command) {
            return .systemConflict("Spotlight")
        }
        if matches(keyCode: 48, modifiers: command) {
            return .systemConflict("App Switcher")
        }
        if matches(keyCode: 50, modifiers: command) {
            return .systemConflict("Window Switcher")
        }
        if matches(keyCode: 123, modifiers: control)
            || matches(keyCode: 124, modifiers: control)
            || matches(keyCode: 125, modifiers: control)
            || matches(keyCode: 126, modifiers: control) {
            return .systemConflict("Spaces")
        }
        if matches(keyCode: 20, modifiers: command | shift)
            || matches(keyCode: 21, modifiers: command | shift)
            || matches(keyCode: 23, modifiers: command | shift) {
            return .systemConflict("Screenshot")
        }
        if matches(keyCode: 53, modifiers: command | option) {
            return .systemConflict("Force Quit")
        }
        if matches(keyCode: 12, modifiers: command | control) {
            return .systemConflict("Lock Screen")
        }

        return nil
    }

    var displayName: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyLabel(for: keyCode)
    }

    private func matches(keyCode: UInt16, modifiers: UInt32) -> Bool {
        self.keyCode == keyCode && carbonModifiers == modifiers
    }

    func matches(event: NSEvent) -> Bool {
        guard let shortcut = NookShortcut(event: event) else { return false }
        return self == shortcut
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func keyLabel(for keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"
        default:
            return keyLabels[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let keyLabels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
        17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "0", 29: "8", 30: "]", 31: "O", 32: "U",
        33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: ";", 40: "K", 41: ",",
        43: "\\", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"
    ]
}

@MainActor
final class NookShortcutManager: ObservableObject {
    @Published private(set) var registrationIssue: NookShortcutIssue?
    @Published private(set) var activeShortcut: NookShortcut

    private let settings: NookSettingsStore
    private let onTrigger: () -> Void
    private let hotKeyID: EventHotKeyID
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var globalKeyMonitor: Any?
    private var lastTriggerDate = Date.distantPast

    init(settings: NookSettingsStore, onTrigger: @escaping () -> Void) {
        self.settings = settings
        self.onTrigger = onTrigger
        hotKeyID = EventHotKeyID(signature: nookShortcutSignature, id: nookShortcutHotKeyIDValue)
        activeShortcut = settings.openNotesShortcut

        installEventHandler()
        installGlobalKeyMonitor()
        registerFromSettings(settings.openNotesShortcut)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
    }

    func setShortcut(_ shortcut: NookShortcut) -> Bool {
        if let issue = shortcut.issue {
            registrationIssue = issue
            return false
        }

        let previousShortcut = activeShortcut
        unregisterHotKey()

        guard registerHotKey(shortcut) else {
            let failedIssue = registrationIssue ?? .unavailable
            _ = registerHotKey(previousShortcut)
            registrationIssue = failedIssue
            return false
        }

        activeShortcut = shortcut
        settings.openNotesShortcut = shortcut
        installGlobalKeyMonitor()
        registrationIssue = nil
        return true
    }

    func clearIssue() {
        registrationIssue = nil
    }

    private func registerFromSettings(_ shortcut: NookShortcut) {
        let previousShortcut = activeShortcut
        unregisterHotKey()
        guard registerHotKey(shortcut) else {
            let failedIssue = registrationIssue ?? .unavailable
            _ = registerHotKey(previousShortcut)
            installGlobalKeyMonitor()
            registrationIssue = failedIssue
            return
        }
        activeShortcut = shortcut
        installGlobalKeyMonitor()
        registrationIssue = nil
    }

    private func installGlobalKeyMonitor() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }

        let monitoredShortcut = activeShortcut
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, monitoredShortcut.matches(event: event) else { return }
            Task { @MainActor in
                self.handleHotKey()
            }
        }
    }

    private func registerHotKey(_ shortcut: NookShortcut) -> Bool {
        if let issue = shortcut.issue {
            registrationIssue = issue
            return false
        }

        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )
        guard status == noErr, let registeredHotKey else {
            registrationIssue = .unavailable
            return false
        }

        hotKey = registeredHotKey
        return true
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        _ = InstallEventHandler(
            GetApplicationEventTarget(),
            nookCarbonEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    fileprivate func handleHotKey() {
        guard Date.now.timeIntervalSince(lastTriggerDate) > 0.2 else { return }
        lastTriggerDate = .now
        onTrigger()
    }
}

/// Carbon requires a C-compatible, capture-free function pointer for the
/// application event handler. The callback immediately hops back to the main
/// actor before touching the manager.
private func nookCarbonEventHandler(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<NookShortcutManager>.fromOpaque(userData).takeUnretainedValue()

    Task { @MainActor in
        manager.handleHotKey()
    }
    return noErr
}

/// Captures the next key-down at the application boundary instead of relying
/// on a one-pixel responder hidden inside SwiftUI. This keeps recording
/// reliable even when the panel is a non-activating utility window.
@MainActor
final class NookShortcutCaptureSession: ObservableObject {
    var onCapture: ((NookShortcut) -> Void)?
    var onInvalid: ((NookShortcutIssue) -> Void)?
    var onCancel: (() -> Void)?
    private var monitor: Any?

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                self.onCancel?()
                return nil
            }

            guard let shortcut = NookShortcut(event: event) else {
                NSSound.beep()
                self.onInvalid?(.modifierRequired)
                return nil
            }

            self.onCapture?(shortcut)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

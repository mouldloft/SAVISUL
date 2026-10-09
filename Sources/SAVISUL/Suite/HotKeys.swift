import AppKit
import Carbon.HIToolbox

/// A Carbon key code with Carbon modifier bits.
struct KeyCombo: Hashable, Codable, Sendable {
    var key: UInt32
    var modifiers: UInt32

    static func control(_ key: Int, option: Bool = true, shift: Bool = false, command: Bool = false) -> KeyCombo {
        var modifiers = controlKey
        if option { modifiers |= optionKey }
        if shift { modifiers |= shiftKey }
        if command { modifiers |= cmdKey }
        return KeyCombo(key: UInt32(key), modifiers: UInt32(modifiers))
    }

    static func option(_ key: Int) -> KeyCombo { KeyCombo(key: UInt32(key), modifiers: UInt32(optionKey)) }

    var glyphs: [String] {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(KeyCombo.name(of: Int(key)))
        return parts
    }

    var label: String { glyphs.joined() }

    static func name(of key: Int) -> String {
        switch key {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Minus: return "−"
        case kVK_ANSI_Equal: return "="
        default: break
        }
        let letters: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0"
        ]
        return letters[key] ?? "#\(key)"
    }
}

/// Global shortcuts through the Carbon hot key API, which needs no privacy permission.
/// Every SAVISUL shortcut goes through here, so one handler can tell them apart.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    static let signature = OSType(0x5341_5653)

    private struct Entry {
        var combo: KeyCombo
        var ref: EventHotKeyRef
        var press: () -> Void
        var release: (() -> Void)?
    }

    private var entries: [UInt32: Entry] = [:]
    private var names: [String: UInt32] = [:]
    private var handler: EventHandlerRef?
    private var counter: UInt32 = 0

    @discardableResult
    func register(_ name: String, _ combo: KeyCombo, press: @escaping () -> Void, release: (() -> Void)? = nil) -> Bool {
        unregister(name)
        installHandler()
        counter += 1
        let id = counter
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.key, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        entries[id] = Entry(combo: combo, ref: ref, press: press, release: release)
        names[name] = id
        return true
    }

    func unregister(_ name: String) {
        guard let id = names.removeValue(forKey: name), let entry = entries.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    func isRegistered(_ name: String) -> Bool { names[name] != nil }

    fileprivate func fire(_ id: UInt32, pressed: Bool) {
        guard let entry = entries[id] else { return }
        if pressed { entry.press() } else { entry.release?() }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = hotKeyID.id
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id, pressed: pressed) }
            return noErr
        }, specs.count, &specs, nil, &handler)
    }
}

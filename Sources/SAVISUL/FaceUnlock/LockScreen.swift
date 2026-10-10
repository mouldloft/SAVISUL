import AppKit
import Carbon.HIToolbox
import IOKit
import IOKit.pwr_mgt

/// The lock screen seen from inside the session: whether it is up, waking it, and typing into its password field.
enum LockScreen {
    /// This user's session is the one on screen, and it is locked.
    static var locked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              (session[kCGSessionOnConsoleKey as String] as? Bool) == true else { return false }
        let flag = session["CGSSessionScreenIsLocked"]
        return (flag as? Bool) == true || (flag as? Int) == 1
    }

    /// The process holding the keyboard's secure input, which the lock screen takes for its password field.
    static func secureInputOwner() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        for user in users where (user["kCGSSessionUserNameKey"] as? String) == NSUserName() {
            if let pid = user["kCGSSessionSecureInputPID"] as? Int { return pid_t(pid) }
        }
        return nil
    }

    /// Whether a password may be typed now: only while this session's screen is locked, when keys go to the lock screen's
    /// field and to no app. macOS 26 doesn't always say who holds secure input there; when it does, it must be the lock screen.
    static var passwordFieldIsUp: Bool {
        guard locked else { return false }
        guard let pid = secureInputOwner() else { return true }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.loginwindow"
    }

    /// Who holds secure input, for the log when the lock screen doesn't look as expected.
    static var keyboardOwner: String {
        let state = IsSecureEventInputEnabled() ? "on" : "off"
        guard let pid = secureInputOwner() else { return "\(state), owner unknown" }
        return "\(state), \(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)")"
    }

    /// Wakes the display and keeps it from dimming for a moment, as a key press would.
    static func wake() {
        var assertion: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("SAVISUL Face Unlock" as CFString, kIOPMUserActiveLocal, &assertion)
    }

    /// Seconds since the last key, click or touch, from the input system, which keeps counting at the lock screen.
    static var secondsSinceInput: Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        defer { IOObjectRelease(service) }
        guard service != 0,
              let idle = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber else { return .infinity }
        return idle.doubleValue / 1_000_000_000
    }

    /// Clears the password field, types the password and presses Return. Before every key it checks the screen is still
    /// locked, so nothing lands in an app if the Mac unlocks another way at that moment. Callers check `passwordFieldIsUp`.
    @discardableResult
    static func type(_ password: String) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard press(kVK_ANSI_A, flags: .maskCommand, source), press(kVK_Delete, flags: [], source) else { return false }
        for chunk in chunks(password) {
            guard locked else { return false }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: down) else { continue }
                if down {
                    chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                }
                event.post(tap: .cghidEventTap)
            }
        }
        return press(kVK_Return, flags: [], source)
    }

    private static func press(_ key: Int, flags: CGEventFlags, _ source: CGEventSource?) -> Bool {
        guard locked else { return false }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    /// The text in pieces of at most `size` UTF-16 units, the most one key event carries, never splitting a character.
    static func chunks(_ text: String, size: Int = 20) -> [[UniChar]] {
        var result: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > size {
                result.append(current)
                current = []
            }
            current += units
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

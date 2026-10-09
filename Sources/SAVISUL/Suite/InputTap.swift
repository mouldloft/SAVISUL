import AppKit
import CoreGraphics

/// One active event tap shared by every feature that has to change or swallow input:
/// the app switcher, ⌘Q protection, Finder shortcuts, the green button and modifier drags.
/// The tap runs on the main run loop, so handlers must answer quickly.
@MainActor
final class InputTap {
    static let shared = InputTap()

    /// Events SAVISUL posts itself carry this marker so handlers leave them alone.
    nonisolated static let marker: Int64 = 0x5341_5653

    /// Return the event to let it through (possibly changed in place), or nil to swallow it.
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private struct Client {
        var id: String
        var priority: Int
        var types: Set<CGEventType.RawValue>
        var run: Handler
    }

    private var clients: [Client] = []
    nonisolated(unsafe) fileprivate static var port: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var running = false

    func add(_ id: String, priority: Int = 0, types: [CGEventType], handler: @escaping Handler) {
        remove(id)
        clients.append(Client(id: id, priority: priority, types: Set(types.map(\.rawValue)), run: handler))
        clients.sort { $0.priority > $1.priority }
        start()
    }

    func remove(_ id: String) {
        clients.removeAll { $0.id == id }
        if clients.isEmpty { stop() }
    }

    func has(_ id: String) -> Bool { clients.contains { $0.id == id } }

    /// Needs Accessibility. Safe to call again after the grant arrives.
    @discardableResult
    func start() -> Bool {
        if running { return true }
        guard !clients.isEmpty, AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: inputTapCallback, userInfo: nil) else {
            return false
        }
        InputTap.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.source = source
        running = true
        return true
    }

    func stop() {
        guard running else { return }
        if let port = InputTap.port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        InputTap.port = nil
        source = nil
        running = false
    }

    fileprivate func dispatch(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == InputTap.marker { return event }
        var current = event
        for client in clients where client.types.contains(type.rawValue) {
            guard let next = client.run(type, current) else { return nil }
            current = next
        }
        return current
    }

    fileprivate func revive() {
        if let port = InputTap.port { CGEvent.tapEnable(tap: port, enable: true) }
    }
}

private func inputTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                              _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { InputTap.shared.revive() }
        return Unmanaged.passUnretained(event)
    }
    nonisolated(unsafe) let incoming = event
    let result = MainActor.assumeIsolated { InputTap.shared.dispatch(type, incoming) }
    guard let result else { return nil }
    return Unmanaged.passUnretained(result)
}

/// Synthetic keyboard input for pasting and for remapping keys in other apps.
enum Keys {
    private static func source() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                           state: .eventSuppressionStateSuppressionInterval)
        return source
    }

    static func tap(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = source()
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: InputTap.marker)
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// ⌘V into whatever app is in front.
    static func paste() { tap(9, flags: .maskCommand) }

    /// Modifiers still held from a shortcut would turn ⌘V into another command, so wait them out.
    @MainActor
    static func whenModifiersReleased(timeout: TimeInterval = 1.2, _ action: @escaping @MainActor () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let held = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            if held.isEmpty || Date() > deadline {
                action()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { MainActor.assumeIsolated { check() } }
            }
        }
        check()
    }
}

import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin, failure-tolerant wrappers over the Accessibility API. Every call can fail when an app is busy,
/// so messaging timeouts are kept short and every result is optional.
enum AX {
    static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }()

    static var trusted: Bool { AXIsProcessTrusted() }

    static func app(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.4)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute) as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let raw = value(element, attribute) as? [AnyObject] else { return [] }
        return raw.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func role(_ element: AXUIElement) -> String? { string(element, kAXRoleAttribute) }
    static func subrole(_ element: AXUIElement) -> String? { string(element, kAXSubroleAttribute) }
    static func title(_ element: AXUIElement) -> String? { string(element, kAXTitleAttribute) }

    static func pid(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    static func point(_ element: AXUIElement, _ attribute: String = kAXPositionAttribute) -> CGPoint? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(raw as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String = kAXSizeAttribute) -> CGSize? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(raw as! AXValue, .cgSize, &size) ? size : nil
    }

    /// Frame in global top-left coordinates, the space Accessibility and Core Graphics share.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = point(element), let size = size(element) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    /// Size, then position, then size again: apps that clamp a window to its screen accept the second size.
    static func setFrame(_ element: AXUIElement, _ frame: CGRect) {
        setSize(element, frame.size)
        setPosition(element, frame.origin)
        setSize(element, frame.size)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    static func windows(_ pid: pid_t) -> [AXUIElement] {
        elements(app(pid), kAXWindowsAttribute)
    }

    /// Nil when the app did not answer, which is different from an app with no windows.
    static func windowList(_ pid: pid_t) -> [AXUIElement]? {
        var result: AnyObject?
        guard AXUIElementCopyAttributeValue(app(pid), kAXWindowsAttribute as CFString, &result) == .success else { return nil }
        return (result as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        element(app(pid), kAXFocusedWindowAttribute)
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var identifier: CGWindowID = 0
        return _AXUIElementGetWindow(element, &identifier) == .success && identifier != 0 ? identifier : nil
    }

    static func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success else { return nil }
        return element
    }

    /// Walks up from any element to the window that contains it.
    static func window(containing element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let node = current else { return nil }
            if role(node) == kAXWindowRole { return node }
            if let window = AX.element(node, kAXWindowAttribute) { return window }
            current = AX.element(node, kAXParentAttribute)
        }
        return nil
    }

    static func isStandardWindow(_ window: AXUIElement) -> Bool {
        let subrole = subrole(window)
        return subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }

    /// Brings one window to the front, switching Spaces if macOS needs to.
    @MainActor
    static func focus(_ window: AXUIElement, pid: pid_t) {
        if bool(window, kAXMinimizedAttribute) == true {
            set(window, kAXMinimizedAttribute, kCFBooleanFalse)
        }
        let app = app(pid)
        set(app, kAXFrontmostAttribute, kCFBooleanTrue)
        set(window, kAXMainAttribute, kCFBooleanTrue)
        perform(window, kAXRaiseAction)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    static func close(_ window: AXUIElement) {
        if let button = element(window, kAXCloseButtonAttribute) { perform(button, kAXPressAction) }
    }

    static func minimize(_ window: AXUIElement) {
        set(window, kAXMinimizedAttribute, kCFBooleanTrue)
    }
}

/// AppKit puts the origin at the bottom left of the primary screen; Accessibility and Core Graphics at its top left.
enum ScreenSpace {
    @MainActor static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    @MainActor static func toAX(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor static func toAppKit(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor static func toAX(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    @MainActor static func toAppKit(_ point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: primaryHeight - point.y)
    }

    @MainActor static var mouseScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The screen holding most of a rectangle given in top-left coordinates.
    @MainActor static func screen(forAX rect: CGRect) -> NSScreen {
        let flipped = toAppKit(rect)
        var best: (NSScreen, CGFloat)?
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(flipped)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if best == nil || area > best!.1 { best = (screen, area) }
        }
        return best?.0 ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The built-in display with a camera housing, if there is one.
    @MainActor static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }
}

/// Apps that own windows, keyed by process.
enum RunningApps {
    @MainActor static func regular() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != me
        }
    }

    /// The .app bundle a helper process belongs to, read from its executable path.
    static func bundlePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

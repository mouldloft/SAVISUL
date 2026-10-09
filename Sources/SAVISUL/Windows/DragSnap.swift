import AppKit

/// ⌃⌘-drag moves a window from anywhere inside it, ⌃⌘ with the right button resizes it from
/// the nearest corner, and dropping on a screen edge or corner lays it out there.
@MainActor
final class DragSnap {
    private struct Drag {
        var window: AXBox
        var start: CGPoint
        var frame: CGRect
        var resize: Bool
        var left: Bool
        var top: Bool
    }

    private struct TitleDrag {
        var point: CGPoint
        var window: AXBox?
        var frame: CGRect?
        var looked = false
    }

    private var drag: Drag?
    private var titleDrag: TitleDrag?
    private var zone: SnapAction?
    private var zoneScreen: NSScreen?
    private let mover = WindowMover()
    private var modifierDrag = false
    private var edgeSnap = false
    private let lookup = DispatchQueue(label: "savisul.titlebar", qos: .userInteractive)

    func enable(modifier: Bool, edges: Bool) {
        modifierDrag = modifier
        edgeSnap = edges
        if modifier || edges {
            if !InputTap.shared.has("drag") {
                InputTap.shared.add("drag", priority: 40, types: [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                                                  .rightMouseDown, .rightMouseDragged, .rightMouseUp]) { [weak self] type, event in
                    guard let self else { return event }
                    return self.handle(type, event)
                }
            }
        } else {
            InputTap.shared.remove("drag")
            drag = nil
            titleDrag = nil
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let point = event.location
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        switch type {
        case .leftMouseDown, .rightMouseDown:
            if modifierDrag && modifiers == [.maskCommand, .maskControl], begin(at: point, resize: type == .rightMouseDown) {
                return nil
            }
            if type == .leftMouseDown && edgeSnap && modifiers.isEmpty { titleDrag = TitleDrag(point: point) }
            return event
        case .leftMouseDragged, .rightMouseDragged:
            if let drag {
                follow(drag, to: point)
                return nil
            }
            if titleDrag != nil {
                if titleDrag?.looked == false {
                    titleDrag?.looked = true
                    lookUpTitle(at: titleDrag!.point)
                }
                if titleDrag?.window != nil, hypot(point.x - titleDrag!.point.x, point.y - titleDrag!.point.y) > 8 { updateZone(point) }
            }
            return event
        case .leftMouseUp, .rightMouseUp:
            if drag != nil {
                finish()
                return nil
            }
            if titleDrag != nil { finishTitleDrag() }
            return event
        default:
            return event
        }
    }

    // MARK: Modifier drag

    private func begin(at point: CGPoint, resize: Bool) -> Bool {
        guard let hit = AX.element(at: point), let window = AX.window(containing: hit), AX.isStandardWindow(window),
              let frame = AX.frame(window), let pid = AX.pid(window), pid != ProcessInfo.processInfo.processIdentifier else { return false }
        if !resize { AX.perform(window, kAXRaiseAction) }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        drag = Drag(window: AXBox(window), start: point, frame: frame, resize: resize,
                    left: point.x < frame.midX, top: point.y < frame.midY)
        return true
    }

    private func follow(_ drag: Drag, to point: CGPoint) {
        let dx = point.x - drag.start.x
        let dy = point.y - drag.start.y
        if drag.resize {
            var frame = drag.frame
            if drag.left {
                frame.origin.x += dx
                frame.size.width -= dx
            } else {
                frame.size.width += dx
            }
            if drag.top {
                frame.origin.y += dy
                frame.size.height -= dy
            } else {
                frame.size.height += dy
            }
            if frame.width < 240 {
                if drag.left { frame.origin.x = drag.frame.maxX - 240 }
                frame.size.width = 240
            }
            if frame.height < 160 {
                if drag.top { frame.origin.y = drag.frame.maxY - 160 }
                frame.size.height = 160
            }
            mover.move(drag.window, origin: drag.left || drag.top ? frame.origin : nil, size: frame.size)
        } else {
            mover.move(drag.window, origin: CGPoint(x: drag.frame.minX + dx, y: drag.frame.minY + dy), size: nil)
            updateZone(point)
        }
    }

    private func finish() {
        guard let drag else { return }
        self.drag = nil
        if let zone, !drag.resize {
            let window = drag.window
            mover.flush {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { Self.snap(window, zone) }
                }
            }
        }
        clearZone()
    }

    // MARK: Title-bar drag

    /// Finds the window whose title bar was grabbed, off the event thread so clicks never wait on it.
    private func lookUpTitle(at point: CGPoint) {
        lookup.async {
            guard let hit = AX.element(at: point), let window = AX.window(containing: hit), AX.isStandardWindow(window),
                  let frame = AX.frame(window), point.y - frame.minY < 40 else { return }
            let role = AX.role(hit) ?? ""
            let controls: Set<String> = [kAXButtonRole, kAXTextFieldRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXPopUpButtonRole,
                                         kAXMenuButtonRole, kAXSliderRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField", "AXTab"]
            guard !controls.contains(role) else { return }
            let box = AXBox(window)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let drag = Suite.shared.windows.dragSnap.titleDrag, drag.point == point else { return }
                    Suite.shared.windows.dragSnap.titleDrag?.window = box
                    Suite.shared.windows.dragSnap.titleDrag?.frame = frame
                }
            }
        }
    }

    private func finishTitleDrag() {
        defer {
            titleDrag = nil
            clearZone()
        }
        guard let zone, let drag = titleDrag, let window = drag.window else { return }
        if let start = drag.frame, let now = AX.frame(window.element), Snapper.close(start, now) { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { Self.snap(window, zone) }
        }
    }

    // MARK: Zones

    private func updateZone(_ point: CGPoint) {
        let appKitPoint = ScreenSpace.toAppKit(point)
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(appKitPoint, $0.frame.insetBy(dx: -1, dy: -1)) }) else {
            clearZone()
            return
        }
        let frame = ScreenSpace.toAX(screen.frame)
        let edge: CGFloat = 4
        let corner: CGFloat = 60
        let nearLeft = point.x <= frame.minX + edge
        let nearRight = point.x >= frame.maxX - edge - 1
        let nearTop = point.y <= frame.minY + edge
        let nearBottom = point.y >= frame.maxY - edge - 1
        var next: SnapAction?
        if nearLeft { next = point.y < frame.minY + corner ? .topLeft : point.y > frame.maxY - corner ? .bottomLeft : .left }
        else if nearRight { next = point.y < frame.minY + corner ? .topRight : point.y > frame.maxY - corner ? .bottomRight : .right }
        else if nearTop { next = point.x < frame.minX + corner ? .topLeft : point.x > frame.maxX - corner ? .topRight : .maximize }
        else if nearBottom && point.x < frame.minX + corner { next = .bottomLeft }
        else if nearBottom && point.x > frame.maxX - corner { next = .bottomRight }
        guard next != zone || screen != zoneScreen else { return }
        zone = next
        zoneScreen = screen
        if let next {
            let visible = ScreenSpace.toAX(screen.visibleFrame)
            Suite.shared.windows.snapper.preview.hold(SnapAction.frame(next, visible: visible, current: visible, cycle: 0))
        } else {
            Suite.shared.windows.snapper.preview.release()
        }
    }

    private func clearZone() {
        zone = nil
        zoneScreen = nil
        Suite.shared.windows.snapper.preview.release()
    }

    private static func snap(_ window: AXBox, _ action: SnapAction) {
        guard let current = AX.frame(window.element) else { return }
        Suite.shared.windows.snapper.apply(action, to: window.element, current: current)
    }
}

/// Applies window moves on a background queue, dropping intermediate positions an app can't keep up with.
final class WindowMover: @unchecked Sendable {
    private let queue = DispatchQueue(label: "savisul.mover", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: (box: AXBox, origin: CGPoint?, size: CGSize?)?
    private var scheduled = false

    func move(_ box: AXBox, origin: CGPoint?, size: CGSize?) {
        lock.lock()
        pending = (box, origin, size)
        let schedule = !scheduled
        scheduled = true
        lock.unlock()
        guard schedule else { return }
        queue.async { [self] in drain() }
    }

    func flush(_ then: @escaping @Sendable () -> Void) {
        queue.async(execute: then)
    }

    private func drain() {
        while true {
            lock.lock()
            guard let job = pending else {
                scheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            if let size = job.size { AX.setSize(job.box.element, size) }
            if let origin = job.origin { AX.setPosition(job.box.element, origin) }
        }
    }
}

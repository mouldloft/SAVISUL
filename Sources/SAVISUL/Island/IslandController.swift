import AppKit
import SwiftUI

/// The island window: a fixed transparent panel over the camera housing. It lets clicks through
/// everywhere except the black shape, and opens when the pointer rests on the notch or a drag arrives.
@MainActor
final class IslandController {
    static let panelSize = NSSize(width: 720, height: 300)

    private let suite: Suite
    private let model: IslandModel
    private var panel: IslandPanel?
    private var monitors: [Any] = []
    private var hoverTask: DispatchWorkItem?
    private var leaveTask: DispatchWorkItem?
    private var dragBoard = NSPasteboard(name: .drag).changeCount
    private var dragWatch: Timer?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var inside = false
    private var enteredBubble = false

    init(suite: Suite) {
        self.suite = suite
        self.model = suite.island
        model.onModeChange = { [weak self] in self?.modeChanged() }
        model.onTakeKey = { [weak self] in self?.panel?.makeKey() }
        model.onReleaseKey = { [weak self] in self?.giveBackKey() }
    }

    func show() {
        if panel == nil { build() }
        place()
        panel?.orderFrontRegardless()
        installMonitors()
    }

    func hide() {
        removeMonitors()
        panel?.orderOut(nil)
    }

    private func build() {
        let panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        let root = IslandRoot(suite: suite, model: model)
        let hosting = NSHostingView(rootView: root.environment(\.colorScheme, .dark))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lostKey() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.orderFrontRegardless() }
        }
    }

    var screen: NSScreen {
        ScreenSpace.notchScreen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place() {
        guard let panel else { return }
        let screen = screen
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            model.notch = CGSize(width: max(right.minX - left.maxX, 120), height: screen.safeAreaInsets.top)
            model.hasNotch = true
        } else {
            let menuBar = max(frame.maxY - screen.visibleFrame.maxY, 24)
            model.notch = CGSize(width: 190, height: min(menuBar, 32))
            model.hasNotch = false
        }
        let center = notchCenterX(screen)
        panel.setFrame(NSRect(x: (center - Self.panelSize.width / 2).rounded(), y: frame.maxY - Self.panelSize.height,
                              width: Self.panelSize.width, height: Self.panelSize.height), display: true)
    }

    private func notchCenterX(_ screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return screen.frame.minX + (left.maxX - screen.frame.minX + right.minX - screen.frame.minX) / 2
        }
        return screen.frame.midX
    }

    // MARK: Pointer

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.pointer(type) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.pointer(type) }
            return event
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// The black shape in screen coordinates, with a little slack so the edge is easy to hit.
    private func shapeRect(slack: CGFloat) -> NSRect {
        let size = IslandLayout.size(for: model, activity: IslandActivity.current(suite))
        let screen = screen
        let center = notchCenterX(screen)
        var rect = NSRect(x: center - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        if model.mode == .collapsed && !model.hasNotch {
            rect = NSRect(x: center - 110, y: screen.frame.maxY - 6, width: 220, height: 6)
        }
        return rect.insetBy(dx: -slack, dy: -slack)
    }

    /// The agent's bubble beside the closed island, when one is showing.
    private func bubbleRect(slack: CGFloat) -> NSRect? {
        guard model.mode == .collapsed else { return nil }
        let activity = IslandActivity.current(suite)
        guard IslandActivity.companion(suite, beside: activity) != nil else { return nil }
        let size = IslandLayout.size(for: model, activity: activity)
        let screen = screen
        let x = notchCenterX(screen) + size.width / 2 + IslandRoot.bubbleGap
        let rect = NSRect(x: x, y: screen.frame.maxY - model.notch.height, width: CompanionBubble.width(model.notch.height), height: model.notch.height)
        return rect.insetBy(dx: -slack, dy: -slack)
    }

    private func pointer(_ type: NSEvent.EventType) {
        let mouse = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown:
            dragBoard = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            trackDrag(mouse)
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
        let inBubble = bubbleRect(slack: 3)?.contains(mouse) == true
        let hit = shapeRect(slack: model.mode == .expanded ? 14 : 3).contains(mouse) || inBubble
        panel?.ignoresMouseEvents = !(hit || model.dragNearby)
        if hit != inside {
            inside = hit
            enteredBubble = inBubble
            hit ? entered() : exited()
        }
    }

    private func entered() {
        leaveTask?.cancel()
        guard model.mode != .expanded, suite.settings.islandHover else { return }
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.inside, NSEvent.pressedMouseButtons == 0 || self.model.dragNearby else { return }
                self.model.expand(self.enteredBubble ? .agents : IslandActivity.openingTab(self.suite))
                if self.suite.settings.islandHaptics { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
            }
        }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: task)
    }

    private func exited() {
        hoverTask?.cancel()
        guard model.mode == .expanded, !model.dragNearby else { return }
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.inside, !self.model.dragNearby else { return }
                self.model.collapse()
            }
        }
        leaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: task)
    }

    /// A drag with content that comes near the notch opens the shelf as a drop target.
    private func trackDrag(_ mouse: NSPoint) {
        guard suite.settings.islandShelf, NSPasteboard(name: .drag).changeCount != dragBoard else { return }
        let screen = screen
        let center = notchCenterX(screen)
        let zone = NSRect(x: center - 260, y: screen.frame.maxY - 90, width: 520, height: 90)
        let near = zone.contains(mouse)
        if near && !model.dragNearby {
            model.dragNearby = true
            panel?.ignoresMouseEvents = false
            model.expand(.files)
            startDragWatch()
        } else if !near && model.dragNearby && !shapeRect(slack: 30).contains(mouse) {
            model.dragNearby = false
            if !inside { model.collapse() }
        }
    }

    private func startDragWatch() {
        dragWatch?.invalidate()
        dragWatch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    timer.invalidate()
                    self.endDrag()
                }
            }
        }
    }

    private func endDrag() {
        guard model.dragNearby else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.dragNearby = false
                self.model.dropTargeted = false
                let mouse = NSEvent.mouseLocation
                self.inside = self.shapeRect(slack: 14).contains(mouse)
                self.panel?.ignoresMouseEvents = !self.inside
                if !self.inside {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, !self.inside else { return }
                            self.model.collapse()
                        }
                    }
                }
            }
        }
    }

    private func modeChanged() {
        let mouse = NSEvent.mouseLocation
        inside = shapeRect(slack: model.mode == .expanded ? 14 : 3).contains(mouse)
        panel?.ignoresMouseEvents = !(inside || model.dragNearby)
        if model.mode == .expanded && !inside && !model.dragNearby && !model.pinned {
            let task = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.inside, !self.model.dragNearby else { return }
                    self.model.collapse()
                }
            }
            leaveTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
        }
    }

    /// Clicking into another app while typing in the island lets it close; the draft stays for next time.
    /// Our own sheets, like the folder picker, keep it open.
    private func lostKey() {
        guard model.holding else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.holding, NSApp.keyWindow == nil, !self.inside else { return }
                self.model.holding = false
                self.model.collapse()
            }
        }
    }

    /// A key window that stays on screen keeps the keyboard; reordering the panel hands it back to the app in front.
    private func giveBackKey() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Opens the island from a shortcut or a menu, as if the pointer were on it.
    func open(_ tab: IslandTab) {
        model.expand(tab)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

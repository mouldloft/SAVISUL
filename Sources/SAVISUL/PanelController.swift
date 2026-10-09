import AppKit
import SwiftUI

final class PopupPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject {
    let model: AppModel
    private var statusItem: NSStatusItem?
    private var panel: PopupPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let hotKey = HotKey()
    private var visibilityTimer: Timer?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func start(showPanel: Bool) {
        model.onHide = { [weak self] in self?.hide(animated: false) }
        model.onShow = { [weak self] in self?.show() }
        model.onChromeChange = { [weak self] in self?.refreshStatusIcon() }
        model.onDockPreferenceChange = { [weak self] in self?.applyDockPolicy() }
        model.onLanguageChange = { [weak self] in
            guard let self else { return }
            MainMenu.install(controller: self, model: self.model)
        }
        model.start()
        installStatusItem()
        panel = makePanel(backdrop: false)
        MainMenu.install(controller: self, model: model)
        HotKey.onPress = { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        model.hotKeyReady = hotKey.register()
        applyDockPolicy()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                self?.checkStatusItem()
                if showPanel { self?.show() }
            }
        }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStatusItem() }
        }
        RunLoop.main.add(timer, forMode: .common)
        visibilityTimer = timer
    }

    func shutdown() {
        model.shutdown()
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "SAVISUL"
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.toolTip = "SAVISUL  ⌃⌥S"
            button.setAccessibilityLabel("SAVISUL")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        refreshStatusIcon()
    }

    private func refreshStatusIcon() {
        statusItem?.button?.image = Mark.statusImage(awake: model.power.lidAwake, recording: model.capture.isRecording)
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggle()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        addItem(to: menu, model.text(.menuSettings), #selector(openSettingsFromMenu))
        if model.capture.isRecording {
            addItem(to: menu, model.text(.capStop), #selector(stopRecordingFromMenu))
        }
        menu.addItem(.separator())
        addItem(to: menu, model.text(.menuQuit), #selector(quitFromMenu), key: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc func openSettingsFromMenu() {
        model.select(.settings)
        show()
    }

    @objc private func stopRecordingFromMenu() {
        model.capture.stopRecording()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func screensChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.checkStatusItem() }
        }
    }

    /// macOS silently hides status items that don't fit next to the notch; fall back to the Dock icon then.
    private func checkStatusItem() {
        let visible = statusItemOnScreen()
        guard visible != model.statusVisible else { return }
        model.statusVisible = visible
        applyDockPolicy()
    }

    private func statusItemOnScreen() -> Bool {
        guard let button = statusItem?.button, let window = button.window, window.isVisible,
              window.occlusionState.contains(.visible) else { return false }
        let frame = window.frame
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }),
              screen.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) else { return false }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let shift = left.minX < screen.frame.minX - 1 ? screen.frame.minX : 0
            let notch = NSRect(x: left.maxX + shift, y: screen.frame.maxY - max(left.height, right.height),
                               width: max(0, right.minX - left.maxX), height: max(left.height, right.height))
            if notch.width > 0, frame.intersects(notch) { return false }
        }
        return true
    }

    private func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy = model.showInDock || !model.statusVisible ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    // MARK: Panel

    private func makePanel(backdrop: Bool) -> PopupPanel {
        let size = NSSize(width: Metrics.panelWidth, height: Metrics.panelHeight)
        let panel = PopupPanel(size: size)
        let host = NSHostingView(rootView: RootView(model: model, backdrop: backdrop))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        if backdrop {
            panel.contentView = host
        } else {
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Mark.roundedMask(radius: Metrics.panelRadius)
            effect.autoresizingMask = [.width, .height]
            effect.addSubview(host)
            panel.contentView = effect
        }
        return panel
    }

    func toggle() {
        if let panel, panel.isVisible, panel.alphaValue > 0.5 {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let panel else { return }
        if panel.isVisible, panel.alphaValue > 0.99 {
            panel.makeKey()
            return
        }
        model.panelWillShow()
        let target = targetFrame(for: panel)
        panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
        installMonitors()
    }

    func hide(animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        model.panelDidHide()
        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue < 0.01 { panel.orderOut(nil) }
            }
        })
    }

    private func targetFrame(for panel: NSPanel) -> NSRect {
        let size = panel.frame.size
        if model.statusVisible, let button = statusItem?.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            let y = max(anchor.minY - size.height - 6, visible.minY + 8)
            return NSRect(origin: NSPoint(x: x, y: y), size: size)
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(origin: NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 10), size: size)
    }

    private func installMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.outsideClick() }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                nonisolated(unsafe) let event = event
                let consumed = MainActor.assumeIsolated { self?.consumeKey(event) ?? false }
                return consumed ? nil : event
            }
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func outsideClick() {
        guard !model.pinned, model.holdOpen == 0, !model.power.busy, let panel else { return }
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) { return }
        if let button = statusItem?.button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        hide()
    }

    private func consumeKey(_ event: NSEvent) -> Bool {
        guard let panel, panel.isVisible, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 53 {
            if model.menuOpen { model.closeMenu() } else { hide() }
            return true
        }
        if flags == .command {
            switch key {
            case "w": hide(); return true
            case "q": NSApp.terminate(nil); return true
            case ",": model.select(.settings); return true
            default: return false
            }
        }
        if panel.firstResponder is NSText { return false }
        if flags.isEmpty, let digit = Int(key), (1...Pane.allCases.count).contains(digit) {
            model.select(Pane.allCases[digit - 1])
            return true
        }
        return false
    }

    // MARK: QA renders

    func dumpPanels(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let panel = makePanel(backdrop: true)
        self.panel = panel
        model.start()
        model.panelWillShow()
        panel.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        panel.orderFrontRegardless()
        let shots: [(String, Pane, Bool, Bool)] = [
            ("energy", .energy, false, false), ("sound", .sound, false, false), ("system", .system, false, false),
            ("system-end", .system, false, true), ("work", .work, false, false), ("work-end", .work, false, true),
            ("tools", .tools, false, false), ("features", .features, false, false), ("automations", .automations, false, false),
            ("automations-edit", .automations, false, false), ("automations-edit-end", .automations, false, true), ("settings", .settings, false, false),
            ("menu", .energy, true, false)
        ]
        func capture(_ index: Int) {
            guard index < shots.count else {
                ClipboardPanel.dump(to: folder) {
                    IslandAgentsRender.dump(to: folder) {
                        IslandHomeRender.dump(to: folder) { IslandStatesRender.dump(to: folder) { NSApp.terminate(nil) } }
                    }
                }
                return
            }
            let shot = shots[index]
            AutomationsPreview.shared.automation = shot.0.hasPrefix("automations-edit") ? AutomationTemplates.all[1] : nil
            model.select(shot.1)
            model.menuOpen = shot.2
            if shot.3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    MainActor.assumeIsolated { self?.model.scrollToEnd += 1 }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let view = self.panel?.contentView else { return }
                    view.layoutSubtreeIfNeeded()
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        let url = folder.appendingPathComponent("panels-\(shot.0).png")
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
                    }
                    capture(index + 1)
                }
            }
        }
        capture(0)
    }
}

@MainActor
enum MainMenu {
    static func install(controller: PanelController, model: AppModel) {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "SAVISUL")
        appMenu.addItem(withTitle: model.text(.mmAbout), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: model.text(.mmSettings), action: #selector(PanelController.openSettingsFromMenu), keyEquivalent: ",")
        settings.target = controller
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: model.text(.mmHide), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: model.text(.mmQuit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: model.text(.mmEdit))
        edit.addItem(withTitle: model.text(.mmUndo), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: model.text(.mmRedo), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: model.text(.mmCut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: model.text(.mmCopy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: model.text(.mmPaste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: model.text(.mmSelectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}

enum SingleInstance {
    static let presentNote = Notification.Name("com.savisul.menu.present")

    /// Returns true when another copy is already running; unless `present` is false, that copy shows its panel.
    static func handOff(present: Bool = true) -> Bool {
        guard !AppInstances.others().isEmpty else { return false }
        if present {
            DistributedNotificationCenter.default().postNotificationName(presentNote, object: nil, userInfo: nil, deliverImmediately: true)
        }
        return true
    }

    static func listen(_ action: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: presentNote, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
    }
}

enum LaunchContext {
    /// Login items are opened with an `oapp` event whose `prdt` parameter is `lgit`.
    static func isLoginLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == 0x6F61_7070 else { return false }
        return event.paramDescriptor(forKeyword: 0x7072_6474)?.enumCodeValue == 0x6C67_6974
    }
}

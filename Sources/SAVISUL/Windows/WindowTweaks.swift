import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// The green button fills the screen instead of opening a new Space, ⌘Q has to be held,
/// and chosen apps quit once their last window closes.
@MainActor
final class WindowTweaks {
    private let me = ProcessInfo.processInfo.processIdentifier

    private var swallowUp = false
    private var zoomed: [CGWindowID: CGRect] = [:]

    private var doubleTap = false
    private var holdStart: Date?
    private var holdApp: NSRunningApplication?
    private var holdTimer: Timer?
    private var lastTap: (app: pid_t, at: Date)?
    private let hud = QuitHUD()
    static let hold: TimeInterval = 0.65

    private var closeTimer: Timer?
    private var closeApps: Set<String> = []
    private var hadWindows: [pid_t: Bool] = [:]
    private var emptyReads: [pid_t: Int] = [:]

    func apply(_ settings: SuiteSettings) {
        if settings.greenButton {
            if !InputTap.shared.has("green") {
                InputTap.shared.add("green", priority: 60, types: [.leftMouseDown, .leftMouseUp]) { [weak self] type, event in
                    guard let self else { return event }
                    return self.green(type, event)
                }
            }
        } else {
            InputTap.shared.remove("green")
        }

        doubleTap = settings.quitGuardDouble
        if settings.quitGuard {
            if !InputTap.shared.has("quit") {
                InputTap.shared.add("quit", priority: 70, types: [.keyDown, .keyUp, .flagsChanged]) { [weak self] type, event in
                    guard let self else { return event }
                    return self.quitKey(type, event)
                }
            }
        } else {
            InputTap.shared.remove("quit")
            cancelHold()
        }

        closeApps = settings.quitOnClose ? Set(settings.quitOnCloseApps) : []
        if closeApps.isEmpty {
            closeTimer?.invalidate()
            closeTimer = nil
            hadWindows = [:]
        } else if closeTimer == nil {
            closeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated { Suite.shared.windows.tweaks.pollClosers() }
            }
        }
    }

    // MARK: Green button

    private func green(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .leftMouseUp {
            if swallowUp {
                swallowUp = false
                return nil
            }
            return event
        }
        guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else { return event }
        let point = event.location
        guard let hit = WindowCatalog.window(at: point), hit.pid != me else { return event }
        let local = CGPoint(x: point.x - hit.frame.minX, y: point.y - hit.frame.minY)
        guard local.x > 36, local.x < 110, local.y > 0, local.y < 48 else { return event }
        guard let element = AX.element(at: point), AX.role(element) == kAXButtonRole else { return event }
        let subrole = AX.subrole(element)
        guard subrole == "AXFullScreenButton" || subrole == "AXZoomButton",
              let window = AX.element(element, kAXWindowAttribute) ?? AX.window(containing: element) else { return event }
        swallowUp = true
        toggleZoom(window)
        return nil
    }

    private func toggleZoom(_ window: AXUIElement) {
        guard let frame = AX.frame(window) else { return }
        let visible = ScreenSpace.toAX(ScreenSpace.screen(forAX: frame).visibleFrame)
        let id = AX.windowID(window) ?? 0
        if Snapper.close(frame, visible), let previous = zoomed[id] {
            AX.setFrame(window, previous)
            zoomed[id] = nil
        } else {
            zoomed[id] = frame
            AX.setFrame(window, visible)
        }
        Suite.shared.windows.snapper.preview.flash(AX.frame(window) ?? visible)
    }

    // MARK: ⌘Q

    private static func exempt(_ app: NSRunningApplication) -> Bool {
        let id = app.bundleIdentifier ?? ""
        return id == "com.apple.finder" || id == Bundle.main.bundleIdentifier || app.activationPolicy != .regular
    }

    private func quitKey(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        switch type {
        case .keyDown:
            guard code == kVK_ANSI_Q,
                  flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]) == .maskCommand,
                  let app = NSWorkspace.shared.frontmostApplication, !Self.exempt(app) else { return event }
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if doubleTap {
                guard !repeated else { return nil }
                if let last = lastTap, last.app == app.processIdentifier, Date().timeIntervalSince(last.at) < 1 {
                    lastTap = nil
                    hud.hide()
                    return event
                }
                lastTap = (app.processIdentifier, Date())
                hud.show(app: app, mode: .again)
                return nil
            }
            guard !repeated, holdStart == nil else { return nil }
            holdStart = Date()
            holdApp = app
            hud.show(app: app, mode: .hold(Self.hold))
            holdTimer = Timer.scheduledTimer(withTimeInterval: Self.hold, repeats: false) { _ in
                MainActor.assumeIsolated { Suite.shared.windows.tweaks.fireQuit() }
            }
            return nil
        case .keyUp:
            if code == kVK_ANSI_Q, holdStart != nil {
                cancelHold()
                return nil
            }
            return event
        case .flagsChanged:
            if holdStart != nil && !flags.contains(.maskCommand) { cancelHold() }
            return event
        default:
            return event
        }
    }

    fileprivate func fireQuit() {
        guard holdStart != nil, let app = holdApp else { return }
        holdStart = nil
        holdTimer = nil
        hud.complete()
        if NSWorkspace.shared.frontmostApplication == app {
            Keys.tap(CGKeyCode(kVK_ANSI_Q), flags: .maskCommand)
        } else {
            app.terminate()
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        guard holdStart != nil else { return }
        holdStart = nil
        holdApp = nil
        hud.hide()
    }

    // MARK: Quit on last window

    fileprivate func pollClosers() {
        let targets = RunningApps.regular().filter { app in app.bundleIdentifier.map { closeApps.contains($0) } ?? false }
        let pids = targets.map(\.processIdentifier)
        guard !pids.isEmpty else {
            hadWindows = [:]
            return
        }
        DispatchQueue.global(qos: .utility).async {
            var counts: [pid_t: Int] = [:]
            for pid in pids {
                if let list = AX.windowList(pid) { counts[pid] = list.filter { AX.isStandardWindow($0) }.count }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Suite.shared.windows.tweaks.closers(counts) }
            }
        }
    }

    private func closers(_ counts: [pid_t: Int]) {
        for (pid, count) in counts {
            if count > 0 {
                hadWindows[pid] = true
                emptyReads[pid] = 0
                continue
            }
            guard hadWindows[pid] == true else { continue }
            emptyReads[pid, default: 0] += 1
            guard emptyReads[pid, default: 0] >= 2, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { continue }
            hadWindows[pid] = nil
            emptyReads[pid] = nil
            let name = app.localizedName ?? ""
            let icon = app.icon
            app.terminate()
            Suite.shared.notify(IslandNotice(symbol: "xmark.circle.fill", tint: Palette.secondary, title: name,
                                             detail: WindowPhrases.quitAfterClose.text, image: icon, duration: 2.2))
        }
    }
}

/// The hold-to-quit ring under the cursor's screen centre.
@MainActor
final class QuitHUD {
    enum Mode: Equatable {
        case hold(TimeInterval)
        case again
    }

    @MainActor @Observable final class State {
        var appName = ""
        var icon: NSImage?
        var mode: Mode = .again
        var started = Date()
        var done = false
    }

    private let state = State()
    private var panel: OverlayPanel?
    private var hideWork: DispatchWorkItem?
    private static let size = NSSize(width: 360, height: 76)

    func show(app: NSRunningApplication, mode: Mode) {
        hideWork?.cancel()
        state.appName = app.localizedName ?? ""
        state.icon = app.icon
        state.mode = mode
        state.started = Date()
        state.done = false
        let panel = self.panel ?? make()
        let screen = ScreenSpace.mouseScreen.visibleFrame
        let frame = NSRect(x: screen.midX - Self.size.width / 2, y: screen.minY + screen.height * 0.16,
                           width: Self.size.width, height: Self.size.height)
        if !panel.isVisible { Glass.fadeIn(panel, to: frame, lift: 8, key: false) } else { panel.setFrame(frame, display: true) }
        if mode == .again { scheduleHide(after: 1.1) }
    }

    func complete() {
        state.done = true
        scheduleHide(after: 0.25)
    }

    func hide() {
        hideWork?.cancel()
        if let panel { Glass.fadeOut(panel, duration: 0.12) }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func make() -> OverlayPanel {
        let panel = OverlayPanel(size: Self.size, key: false, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 3))
        panel.ignoresMouseEvents = true
        panel.contentView = Glass.host(QuitHUDView(state: state), size: Self.size, radius: 22)
        self.panel = panel
        return panel
    }
}

private struct QuitHUDView: View {
    let state: QuitHUD.State

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if case .hold(let duration) = state.mode {
                    TimelineView(.animation) { context in
                        let progress = state.done ? 1 : min(context.date.timeIntervalSince(state.started) / duration, 1)
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                        Circle().trim(from: 0, to: progress)
                            .stroke(Palette.danger, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
                if let icon = state.icon {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    KeyCaps(keys: ["⌘", "Q"], size: 18)
                    Text(state.mode == .again ? WindowPhrases.pressAgain.text : WindowPhrases.holdToQuit.text)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                }
                Text(state.appName).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum WindowPhrases {
    static let holdToQuit = Phrase("Hold to quit", ru: "Удерживайте, чтобы выйти", uk: "Утримуйте, щоб вийти", fr: "Maintenez pour quitter")
    static let pressAgain = Phrase("Press again to quit", ru: "Нажмите ещё раз для выхода", uk: "Натисніть ще раз для виходу", fr: "Appuyez encore pour quitter")
    static let quitAfterClose = Phrase("Quit after its last window closed", ru: "Закрыто вместе с последним окном", uk: "Закрито разом з останнім вікном", fr: "Quitté avec sa dernière fenêtre")
}
